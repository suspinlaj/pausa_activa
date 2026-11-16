import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart' hide Menu, MenuItem;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/legacy.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();
  WindowOptions windowOptions = const WindowOptions(
    size: Size(400, 620),
    center: true,
    title: 'Pausa Activa',
    backgroundColor: Colors.transparent,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setOpacity(0.88);
    if (Platform.isWindows) {
      await windowManager.setSkipTaskbar(true);
    }
  });

  runApp(const PausaActivaApp());
}

class PausaActivaApp extends StatelessWidget {
  const PausaActivaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pausa Activa',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.teal,
        scaffoldBackgroundColor: const Color(0xFF1E1E1E).withValues(alpha: 0.88),
      ),
      home: const TemporizadorScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class TemporizadorScreen extends StatefulWidget {
  const TemporizadorScreen({super.key});

  @override
  State<TemporizadorScreen> createState() => _TemporizadorScreenState();
}

class _TemporizadorScreenState extends State<TemporizadorScreen>
    with TrayListener, WindowListener {
  Timer? _timer;
  int _minutos = 45;
  int _segundosRestantes = 0;
  bool _activo = false;
  bool _mostrandoEjercicios = false;
  int _notifId = 0;

  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    windowManager.addListener(this);
    _inicializarNotificaciones();
    _inicializarBandeja();
  }

  // Cuando pulses el botón nativo de minimizar (- en Windows o círculo amarillo en Mac)
  @override
  void onWindowMinimize() async {
    if (Platform.isWindows) {
      await windowManager.setSkipTaskbar(true);
      await windowManager.hide();
    }
  }

  // Cuando pulses la X (círculo rojo en Mac o X en Windows), se cierra del todo
  @override
  void onWindowClose() async {
    await trayManager.destroy();
    exit(0);
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _inicializarBandeja() async {
    String iconPath = Platform.isWindows
        ? 'assets/app_icon.ico'
        : 'assets/tray_icon.png';

    await trayManager.setIcon(iconPath);
    await _actualizarMenuBandeja();
  }

  Future<void> _actualizarMenuBandeja({bool soloTiempo = false}) async {
    String tiempoStr = _formatearTiempo(_segundosRestantes);
    String estadoTexto = _activo
        ? 'Próxima pausa en: $tiempoStr'
        : 'Temporizador detenido';

    if (Platform.isMacOS) {
      await trayManager.setTitle(_activo ? tiempoStr : '');
    }
    await trayManager.setToolTip(estadoTexto);

    if (soloTiempo) return;

    Menu menu = Menu(
      items: [
        MenuItem(
          key: 'estado',
          label: estadoTexto,
          disabled: true,
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'abrir',
          label: 'Abrir Pausa Activa',
        ),
        MenuItem(
          key: 'toggle',
          label: _activo ? 'Detener temporizador' : 'Iniciar temporizador',
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'salir',
          label: 'Cerrar aplicación',
        ),
      ],
    );
    await trayManager.setContextMenu(menu);
  }

  // Eventos al interactuar con el icono de la bandeja / barra superior
  @override
  void onTrayIconMouseDown() async {
    await _actualizarMenuBandeja();
    await trayManager.popUpContextMenu();
  }

  @override
  void onTrayIconRightMouseDown() async {
    await _actualizarMenuBandeja();
    await trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'abrir':
        await _mostrarVentana();
        break;
      case 'toggle':
        _toggleTemporizador(ocultarAlIniciar: false);
        break;
      case 'salir':
        await trayManager.destroy();
        exit(0);
    }
  }
Future<void> _mostrarVentana() async {
    if (Platform.isWindows) {
      await windowManager.setSkipTaskbar(false);
    }
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _ocultarEnBandeja() async {
    if (Platform.isWindows) {
      await windowManager.setSkipTaskbar(true);
      await windowManager.hide();
    } else if (Platform.isMacOS) {
      // En macOS, minimize() mantiene activo el icono de la barra superior
      await windowManager.minimize();
    }
  }

  Future<void> _inicializarNotificaciones() async {
    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const WindowsInitializationSettings initializationSettingsWindows =
        WindowsInitializationSettings(
      appName: 'Pausa Activa',
      appUserModelId: 'com.susana.pausaactiva',
      guid: '81a24178-8538-4510-9651-824b3113517a',
      iconPath: 'assets/app_icon.ico',
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      macOS: initializationSettingsDarwin,
      windows: initializationSettingsWindows,
    );

    await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        await _mostrarVentana();
        if (mounted) {
          setState(() {
            _mostrandoEjercicios = true;
          });
        }
      },
    );

    if (Platform.isMacOS) {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    }
  }

  void _toggleTemporizador({bool ocultarAlIniciar = true}) async {
    setState(() {
      _activo = !_activo;
      if (_activo) {
        _segundosRestantes = _minutos * 60;
        _iniciarCuentaAtras();
      } else {
        _timer?.cancel();
        _segundosRestantes = 0;
      }
    });

    await _actualizarMenuBandeja();

    if (_activo && ocultarAlIniciar) {
      await _ocultarEnBandeja();
    }
  }

  void _iniciarCuentaAtras() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) return;
      if (_segundosRestantes > 1) {
        setState(() {
          _segundosRestantes--;
        });
        await _actualizarMenuBandeja(soloTiempo: true);
      } else {
        _timer?.cancel();
        setState(() {
          _segundosRestantes = 0;
          _activo = false;
          _mostrandoEjercicios = true;
        });
        await _actualizarMenuBandeja();
        await _mostrarNotificacion();
        await _mostrarVentana();
      }
    });
  }

  void _completarPausa() async {
    setState(() {
      _mostrandoEjercicios = false;
      _activo = true;
      _segundosRestantes = _minutos * 60;
    });
    _iniciarCuentaAtras();
    await _actualizarMenuBandeja();
    await _ocultarEnBandeja();
  }

  String _formatearTiempo(int totalSegundos) {
    final int min = totalSegundos ~/ 60;
    final int seg = totalSegundos % 60;
    return '${min.toString().padLeft(2, '0')}:${seg.toString().padLeft(2, '0')}';
  }

  Future<void> _mostrarNotificacion() async {
    _notifId++;
    const DarwinNotificationDetails darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    const WindowsNotificationDetails windowsDetails = WindowsNotificationDetails();

    const NotificationDetails notificationDetails = NotificationDetails(
      macOS: darwinDetails,
      windows: windowsDetails,
    );

    await flutterLocalNotificationsPlugin.show(
      id: _notifId,
      title: '¡Hora de la pausa activa!',
      body: 'Ver los ejercicios!! ᕙ(  •̀ ᗜ •́  )ᕗ.',
      notificationDetails: notificationDetails,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_mostrandoEjercicios ? 'Ejercicios' : 'Pausa Activa'),
        backgroundColor: const Color(0xFF2D2D30),
        leading: _mostrandoEjercicios
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _mostrandoEjercicios = false),
              )
            : null,
      ),
      body: _mostrandoEjercicios ? _buildEjercicios() : _buildConfiguracion(),
    );
  }

  Widget _buildConfiguracion() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _activo ? 'Próxima pausa en:' : 'Avisarme cada:',
              style: const TextStyle(fontSize: 18, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            if (_activo)
              Text(
                _formatearTiempo(_segundosRestantes),
                style: const TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.bold,
                  color: Colors.tealAccent,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 32),
                    onPressed: () {
                      if (_minutos > 5) setState(() => _minutos -= 5);
                    },
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '$_minutos min',
                    style: const TextStyle(
                        fontSize: 44, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, size: 32),
                    onPressed: () {
                      if (_minutos < 120) setState(() => _minutos += 5);
                    },
                  ),
                ],
              ),
            const SizedBox(height: 40),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _activo ? Colors.redAccent : Colors.tealAccent[700],
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              ),
              onPressed: () => _toggleTemporizador(ocultarAlIniciar: true),
              child: Text(
                _activo ? 'Detener Temporizador' : 'Iniciar Temporizador',
                style: const TextStyle(fontSize: 18, color: Colors.white),
              ),
            ),
            const SizedBox(height: 20),

          ],
        ),
      ),
    );
  }

  Widget _buildEjercicios() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 20),
        _tarjetaEjercicio('Rutina de estiramientos', 'assets/rutina.png'),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.tealAccent[700],
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          onPressed: _completarPausa,
          icon: const Icon(Icons.check_circle_outline, color: Colors.white),
          label: const Text(
            'He terminado',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _tarjetaEjercicio(String titulo, String imagePath) {
    return Card(
      color: const Color(0xFF2D2D30),
      margin: const EdgeInsets.only(bottom: 20),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          children: [
            Text(titulo, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                imagePath,
                width: double.infinity,
                fit: BoxFit.contain,
              ),
            ),
          ],
        ),
      ),
    );
  }
}