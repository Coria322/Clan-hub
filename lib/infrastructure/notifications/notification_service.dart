import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../task/task_repository.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

class NotificationService {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  NotificationService() {
    _initializeNotifications();
  }

  Future<void> _initializeNotifications() async {
    tz.initializeTimeZones();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: null,
    );

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  Future<void> requestPermissions() async {
    if (Platform.isAndroid) {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestExactAlarmsPermission();
    }
  }

  // Sincronizar un snapshot de tareas y recrear alarmas
  void syncTaskAlarms(List<TaskModel> tasks, String currentUserUid) async {
    // 1. Cancelar todo
    await flutterLocalNotificationsPlugin.cancelAll();

    // 2. Filtrar tareas pendientes que tienen deadline a futuro
    //    Aceptamos: Tareas asignadas a TI, y tareas SIN ASIGNAR.
    final myPendingFutureTasks = tasks.where((t) {
      if (t.assignedTo != null && t.assignedTo != currentUserUid) return false;
      if (!t.isPending) return false;
      if (t.deadline == null) return false;
      // Mantenerla viva hasta 10 min despues del deadline para el ultimo aviso
      if (t.deadline!.add(const Duration(minutes: 10)).isBefore(DateTime.now())) return false;
      return true;
    }).toList();

    // 3. Programar recordatorios (24h, 12h, 1h)
    for (var task in myPendingFutureTasks) {
      _scheduleTaskAlarms(task);
    }
  }

  Future<void> _scheduleTaskAlarms(TaskModel task) async {
    final deadline = task.deadline!;
    final now = DateTime.now();

    // Alarmas requeridas
    final offsetsMin = [24 * 60, 12 * 60, 60, -10]; 

    for (int i = 0; i < offsetsMin.length; i++) {
        final alertTime = deadline.subtract(Duration(minutes: offsetsMin[i]));
        
        if (alertTime.isAfter(now)) {
            // Generar un id único para esta notificación
            final int id = "${task.id}_${offsetsMin[i]}".hashCode;
            
            // Determinar texto dinámico
            final String title;
            final String body;
            
            if (offsetsMin[i] == -10) {
              title = '¡Tarea Vencida! 🚨';
              body = 'La tarea "${task.title}" venció hace 10 minutos. ¡Aún puedes salvarla!';
            } else {
              final String label = offsetsMin[i] == 60 ? "1 hora" : "${offsetsMin[i] ~/ 60} horas";
              title = '¡A $label de vencer! ⏳';
              body = 'La tarea "${task.title}" vence pronto.';
            }
            
            await flutterLocalNotificationsPlugin.zonedSchedule(
              id,
              title,
              body,
              tz.TZDateTime.from(alertTime, tz.local),
              const NotificationDetails(
                android: AndroidNotificationDetails(
                  'task_deadline_channel',
                  'Recordatorios de Tareas',
                  channelDescription: 'Canal de notificaciones para vencimiento de tareas',
                  importance: Importance.max,
                  priority: Priority.high,
                ),
              ),
              androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
              uiLocalNotificationDateInterpretation:
                  UILocalNotificationDateInterpretation.absoluteTime,
            );
        }
    }
  }
}
