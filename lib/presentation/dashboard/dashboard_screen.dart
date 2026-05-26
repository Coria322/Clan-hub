import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../application/providers/household_provider.dart';
import '../../infrastructure/auth/auth_repository.dart';
import '../../infrastructure/dashboard/dashboard_repository.dart';
import '../../infrastructure/task/task_repository.dart';

// Riverpod providers para consumo en tiempo real
final dashboardMembersProvider = FutureProvider.autoDispose.family<Map<String, String>, String>((ref, householdId) {
  return ref.watch(dashboardRepositoryProvider).getHouseholdMemberNames(householdId);
});

// Usamos record para parámetros
typedef CompletedTasksArg = ({String householdId, String weekKey});
final dashboardCompletedTasksProvider = StreamProvider.autoDispose.family<List<TaskModel>, CompletedTasksArg>((ref, arg) {
  return ref.watch(dashboardRepositoryProvider).watchTasksForWeek(arg.householdId, arg.weekKey);
});

final dashboardPendingTasksProvider = StreamProvider.autoDispose.family<List<TaskModel>, String>((ref, householdId) {
  return ref.watch(dashboardRepositoryProvider).watchPendingTasks(householdId);
});

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  late DateTime _referenceDate;

  @override
  void initState() {
    super.initState();
    _referenceDate = DateTime.now(); // Comenzamos en la semana actual
  }

  void _previousWeek() {
    setState(() {
      _referenceDate = _referenceDate.subtract(const Duration(days: 7));
    });
  }

  void _nextWeek() {
    setState(() {
      _referenceDate = _referenceDate.add(const Duration(days: 7));
    });
  }

  bool _isCurrentWeek() {
    final now = DateTime.now();
    return TaskRepository.calculateWeekKey(_referenceDate) ==
        TaskRepository.calculateWeekKey(now);
  }

  String _formatWeekRange() {
    final utc = _referenceDate.toUtc();
    final dayOfWeek = utc.weekday;
    final monday = utc.subtract(Duration(days: dayOfWeek - 1));
    final sunday = monday.add(const Duration(days: 6));

    final formatter = DateFormat('dd MMM', 'es_ES');
    return '${formatter.format(monday)} - ${formatter.format(sunday)}';
  }

  // Colores constantes basados en hash del id
  Color _getColorForId(String id, bool isOverdue) {
    if (isOverdue) return const Color(0xFFAC3509); // Coral cálido para vencidas
    
    final colors = [
      const Color(0xFF4352A5), // Soft Indigo
      const Color(0xFFFE6F42), // Warm Coral Light Container
      const Color(0xFF066721), // Country Earthy Green
      const Color(0xFF5C6BC0), // Medium Indigo
      const Color(0xFF2C8138), // Earthy Green Accent
      const Color(0xFFAC3509), // Warm Coral Dark Accent
    ];
    return colors[id.hashCode.abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final householdId = ref.watch(activeHouseholdProvider);
    if (householdId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final weekKey = TaskRepository.calculateWeekKey(_referenceDate);
    final isCurrent = _isCurrentWeek();

    final membersAsync = ref.watch(dashboardMembersProvider(householdId));
    final completedTasksAsync = ref.watch(dashboardCompletedTasksProvider((householdId: householdId, weekKey: weekKey)));
    final pendingTasksAsync = ref.watch(dashboardPendingTasksProvider(householdId));

    final isLoading = membersAsync.isLoading ||
                      completedTasksAsync.isLoading ||
                      pendingTasksAsync.isLoading;

    if (membersAsync.hasError) return Scaffold(body: Center(child: Text('Error members: ${membersAsync.error}')));
    if (completedTasksAsync.hasError) return Scaffold(body: Center(child: SelectableText('Error completedTasks: ${completedTasksAsync.error}')));
    if (pendingTasksAsync.hasError) return Scaffold(body: Center(child: SelectableText('Error pendingTasks: ${pendingTasksAsync.error}')));

    if (isLoading && !membersAsync.hasValue && !completedTasksAsync.hasValue) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dashboard')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final members = membersAsync.value ?? {};
    final completedTasks = completedTasksAsync.value ?? [];
    final pendingTasks = pendingTasksAsync.value ?? [];

    int overdueCount = 0;
    for (var task in pendingTasks) {
      if (task.isOverdue) {
        overdueCount++;
      }
    }

    // Calcular estadísticas de participación + Vencidas
    final counts = <String, int>{};
    for (var task in completedTasks) {
      if (task.completedBy != null) {
        counts[task.completedBy!] = (counts[task.completedBy!] ?? 0) + 1;
      }
    }

    // Pie chart base = Total Tareas Completadas (semana) + Vencidas (globales o semana actual)
    final totalTasksForPie = completedTasks.length + overdueCount;
    final List<CategoryWeeklyStat> stats = [];

    for (final entry in counts.entries) {
      final uid = entry.key;
      final count = entry.value;
      stats.add(CategoryWeeklyStat(
        id: uid,
        displayName: members[uid] ?? 'Desconocido',
        count: count,
        percentage: totalTasksForPie == 0 ? 0 : (count / totalTasksForPie) * 100,
      ));
    }

    if (overdueCount > 0) {
      stats.add(CategoryWeeklyStat(
        id: 'overdue',
        displayName: 'Vencidas',
        count: overdueCount,
        percentage: totalTasksForPie == 0 ? 0 : (overdueCount / totalTasksForPie) * 100,
        isOverdueCategory: true,
      ));
    }

    // Ordenar de mayor a menor tamaño en el pie
    stats.sort((a, b) => b.count.compareTo(a.count));

    final unassignedCounts = <String, int>{};

    for (var task in completedTasks) {
       if (task.assignedTo == null && task.completedBy != null) {
          unassignedCounts[task.completedBy!] = (unassignedCounts[task.completedBy!] ?? 0) + 1;
       }
    }
    
    final List<UnassignedStat> unassignedStats = unassignedCounts.entries.map((e) {
       return UnassignedStat(e.key, members[e.key] ?? 'Desconocido', e.value);
    }).toList()..sort((a, b) => b.count.compareTo(a.count));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Inter')),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Period Toggle & Current Week Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (isCurrent)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_today, size: 14, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 6),
                        Text('Semana actual', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                      ],
                    ),
                  )
                else
                  const SizedBox.shrink(),
                
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left, size: 20),
                        onPressed: _previousWeek,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                      Text(
                        _formatWeekRange(),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right, size: 20),
                        onPressed: isCurrent ? null : _nextWeek,
                        color: isCurrent ? Colors.grey : null,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Bento Grid Layout
            // Card A: Contribution
            _buildContributionCard(stats, totalTasksForPie),
            const SizedBox(height: 16),
            
            // Card B: Initiative Score
            _buildInitiativeCard(unassignedStats),
            const SizedBox(height: 16),
            
            // Card C: Activity Streak (real heatmap)
            _buildActivityStreakCard(householdId),
            const SizedBox(height: 16),

            // Card D: Nota del Clan
            _buildClanNoteCard(householdId),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildContributionCard(List<CategoryWeeklyStat> stats, int total) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4352A5).withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Distribución de Tareas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // Ring Chart (using fl_chart)
              SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 45,
                        sections: stats.isEmpty 
                          ? [PieChartSectionData(color: Colors.grey.shade300, value: 1, radius: 15, showTitle: false)]
                          : stats.map((s) => PieChartSectionData(
                              color: _getColorForId(s.id, s.isOverdueCategory),
                              value: s.count.toDouble(),
                              radius: 15,
                              showTitle: false,
                            )).toList(),
                      ),
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(total.toString(), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
                          const Text('tareas', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Legends
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: stats.isEmpty 
                      ? [const Text('Sin datos', style: TextStyle(color: Colors.grey))] 
                      : stats.map((s) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Container(width: 10, height: 10, decoration: BoxDecoration(color: _getColorForId(s.id, s.isOverdueCategory), shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.displayName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 4),
                                  Container(
                                    height: 6,
                                    width: double.infinity,
                                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
                                    child: FractionallySizedBox(
                                      alignment: Alignment.centerLeft,
                                      widthFactor: s.percentage / 100,
                                      child: Container(decoration: BoxDecoration(color: _getColorForId(s.id, s.isOverdueCategory), borderRadius: BorderRadius.circular(10))),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('${s.percentage.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInitiativeCard(List<UnassignedStat> unassigned) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(color: const Color(0xFF4352A5).withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Iniciativa ⚡️', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          if (unassigned.isEmpty)
            const Text('Nadie completó tareas sin asignar.', style: TextStyle(fontSize: 13, color: Colors.grey))
          else
            ...unassigned.map((s) {
              final max = unassigned.first.count;
              final widthFactor = max > 0 ? (s.count / max) : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(s.displayName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        Text('${s.count} voluntarias', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFE6F42).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.all(4),
                      child: FractionallySizedBox(
                        widthFactor: widthFactor,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFFE6F42),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 8),
                          child: (widthFactor == 1.0) 
                              ? const Text('EXPERTO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white))
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 8),
          const Text('Mide tareas completadas sin que hayan sido asignadas.', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildActivityStreakCard(String householdId) {
    return StreamBuilder<List<TaskModel>>(
      stream: ref.watch(taskRepositoryProvider).watchCompletedTasks(householdId),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
        }
        final tasks = snap.data!;
        
        final today = DateTime.now();
        final currentMonday = today.subtract(Duration(days: today.weekday - 1));
        final startDate = DateUtils.dateOnly(currentMonday.subtract(const Duration(days: 21))); // 4 weeks ago
        
        final Map<DateTime, int> completedCounts = {};
        final Map<DateTime, int> allTimeCounts = {};
        
        for (final t in tasks) {
          if (t.completedAt != null) {
            final d = DateUtils.dateOnly(t.completedAt!);
            allTimeCounts[d] = (allTimeCounts[d] ?? 0) + 1;
            if (!d.isBefore(startDate)) {
              completedCounts[d] = (completedCounts[d] ?? 0) + 1;
            }
          }
        }
        
        int maxCount = 1;
        for (final count in completedCounts.values) {
          if (count > maxCount) maxCount = count;
        }
        
        int bestStreak = 0;
        if (allTimeCounts.isNotEmpty) {
          final sortedDates = allTimeCounts.keys.toList()..sort();
          int tempStreak = 1;
          bestStreak = 1;
          for (int i = 1; i < sortedDates.length; i++) {
            if (sortedDates[i].difference(sortedDates[i - 1]).inDays == 1) {
              tempStreak++;
              if (tempStreak > bestStreak) bestStreak = tempStreak;
            } else {
              tempStreak = 1;
            }
          }
        }

        final heatmapData = <double>[];
        int todayIndex = -1;
        for (int i = 0; i < 28; i++) {
          final d = startDate.add(Duration(days: i));
          if (DateUtils.isSameDay(d, today)) todayIndex = i;
          
          if (d.isAfter(today)) {
            heatmapData.add(-1.0);
          } else {
            final count = completedCounts[d] ?? 0;
            heatmapData.add(count / maxCount);
          }
        }

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFF1F5F9)),
            boxShadow: [
              BoxShadow(color: const Color(0xFF4352A5).withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Racha de Actividad del Clan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text('Mejor: $bestStreak días', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (var d in ['L', 'M', 'M', 'J', 'V', 'S', 'D'])
                    Expanded(child: Center(child: Text(d, style: const TextStyle(fontSize: 10, color: Colors.grey)))),
                ],
              ),
              const SizedBox(height: 8),
              _buildHeatmapGrid(heatmapData, todayIndex),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeatmapGrid(List<double> heatmapData, int todayIndex) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: 28,
      itemBuilder: (ctx, i) {
        final val = heatmapData[i];
        if (val == -1.0) {
          return Container(decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid)));
        }
        if (val == 0.0) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest, 
              borderRadius: BorderRadius.circular(6),
              border: (i == todayIndex) ? Border.all(color: const Color(0xFFFE6F42), width: 2) : null,
            )
          );
        }
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2 + (val * 0.8)),
            borderRadius: BorderRadius.circular(6),
            border: (i == todayIndex) ? Border.all(color: const Color(0xFFFE6F42), width: 2) : null,
          ),
        );
      },
    );
  }

  Widget _buildClanNoteCard(String householdId) {
    final currentUid = ref.read(authRepositoryProvider).currentUser?.uid;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('households').doc(householdId).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() as Map<String, dynamic>?;
        final note = data?['note'] as String?;
        final isAdmin = data?['adminUid'] == currentUid;
        final hasNote = note != null && note.isNotEmpty;

        // No admin sin nota: no mostrar nada
        if (!hasNote && !isAdmin) return const SizedBox.shrink();

        // Admin sin nota: solo mostrar indicador sutil (solo lectura en dashboard)
        if (!hasNote && isAdmin) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.push_pin_outlined, size: 16, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)),
                const SizedBox(width: 8),
                Text(
                  'Sin nota del Clan. Ve a Tareas para agregar una.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          );
        }

        // Nota existente
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)),
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nota del Clan',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF4352A5),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    note!,
                    style: const TextStyle(
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                      color: Color(0xFF454651),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const Positioned(
                right: 0,
                bottom: 0,
                child: Opacity(
                  opacity: 0.08,
                  child: Icon(Icons.push_pin_outlined, size: 40, color: Color(0xFF4352A5)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class UnassignedStat {
  final String uid;
  final String displayName;
  final int count;
  UnassignedStat(this.uid, this.displayName, this.count);
}

class OwnershipStat {
  final String ownerUid;
  final String ownerName;
  final Map<String, int> completedByCounts;
  OwnershipStat(this.ownerUid, this.ownerName, this.completedByCounts);
  
  int get totalAssignedAndCompleted => completedByCounts.values.fold(0, (a, b) => a + b);
}
