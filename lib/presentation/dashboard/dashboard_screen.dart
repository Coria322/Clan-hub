import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../application/providers/household_provider.dart';
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
  int _selectedViewIndex = 0;

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
    if (isOverdue) return Colors.redAccent.shade700; // Color especial para vencidos
    
    final colors = [
      const Color(0xFF42A5F5),
      const Color(0xFF66BB6A),
      const Color(0xFFFFA726),
      const Color(0xFFAB47BC),
      const Color(0xFF26C6DA),
      const Color(0xFF8D6E63),
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
    final title = isCurrent ? 'Semana Actual' : 'Semana Histórica';

    final membersAsync = ref.watch(dashboardMembersProvider(householdId));
    final completedTasksAsync = ref.watch(dashboardCompletedTasksProvider((householdId: householdId, weekKey: weekKey)));
    final pendingTasksAsync = ref.watch(dashboardPendingTasksProvider(householdId));

    final isLoading = membersAsync.isLoading ||
                      completedTasksAsync.isLoading ||
                      pendingTasksAsync.isLoading;

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
    int pendingsNotOverdue = 0;
    for (var task in pendingTasks) {
      if (task.isOverdue) {
        overdueCount++;
      } else {
        pendingsNotOverdue++;
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
    final ownershipCounts = <String, Map<String, int>>{};

    for (var task in completedTasks) {
       if (task.assignedTo == null && task.completedBy != null) {
          unassignedCounts[task.completedBy!] = (unassignedCounts[task.completedBy!] ?? 0) + 1;
       }
       if (task.assignedTo != null && task.completedBy != null) {
          final owner = task.assignedTo!;
          final solver = task.completedBy!;
          ownershipCounts.putIfAbsent(owner, () => {});
          ownershipCounts[owner]![solver] = (ownershipCounts[owner]![solver] ?? 0) + 1;
       }
    }
    
    final List<UnassignedStat> unassignedStats = unassignedCounts.entries.map((e) {
       return UnassignedStat(e.key, members[e.key] ?? 'Desconocido', e.value);
    }).toList()..sort((a, b) => b.count.compareTo(a.count));
    
    final List<OwnershipStat> ownershipStats = ownershipCounts.entries.map((e) {
       return OwnershipStat(e.key, members[e.key] ?? 'Desconocido', e.value);
    }).toList()..sort((a,b) => b.totalAssignedAndCompleted.compareTo(a.totalAssignedAndCompleted));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard Analítico'),
      ),
      body: Column(
        children: [
          // Navigación temporal
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _previousWeek,
                ),
                Column(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatWeekRange(),
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.primary, fontSize: 13),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: isCurrent ? null : _nextWeek,
                  color: isCurrent ? Colors.grey : null,
                ),
              ],
            ),
          ),
          
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Participación')),
                ButtonSegment(value: 1, label: Text('Iniciativa')),
                ButtonSegment(value: 2, label: Text('Salvadores')),
              ],
              selected: {_selectedViewIndex},
              onSelectionChanged: (s) => setState(() => _selectedViewIndex = s.first),
              style: SegmentedButton.styleFrom(
                 textStyle: const TextStyle(fontSize: 12),
                 padding: const EdgeInsets.symmetric(horizontal: 4)
              ),
            ),
          ),

          Expanded(
            child: CustomScrollView(
              slivers: [
                // Resumen Global
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        _buildOverviewCard(
                          context: context,
                          title: 'Completadas',
                          count: completedTasks.length,
                          icon: Icons.check_circle_outline,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 8),
                         _buildOverviewCard(
                          context: context,
                          title: 'Pendientes',
                          count: pendingsNotOverdue,
                          icon: Icons.hourglass_empty,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                         _buildOverviewCard(
                          context: context,
                          title: 'Vencidas',
                          count: overdueCount,
                          icon: Icons.warning_amber_rounded,
                          color: Colors.redAccent,
                        ),
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 8)),

                ..._getSelectedSlivers(
                  stats: stats,
                  unassignedStats: unassignedStats,
                  ownershipStats: ownershipStats,
                  members: members,
                ),
                
                const SliverToBoxAdapter(child: SizedBox(height: 80)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewCard({
    required BuildContext context, 
    required String title, 
    required int count,
    required IconData icon,
    required Color color
  }) {
    return Expanded(
      child: Card(
        elevation: 0,
        color: color.withOpacity(0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color.withOpacity(0.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 4),
              Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color.withOpacity(0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPieChart(List<CategoryWeeklyStat> stats) {
    return Container(
      height: 280,
      padding: const EdgeInsets.all(20),
      child: PieChart(
        PieChartData(
          sectionsSpace: 2,
          centerSpaceRadius: 60,
          sections: stats.map((stat) {
            return PieChartSectionData(
              color: _getColorForId(stat.id, stat.isOverdueCategory),
              value: stat.count.toDouble(),
              title: '${stat.percentage.toStringAsFixed(1)}%',
              radius: 50,
              titleStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                shadows: [Shadow(color: Colors.black45, blurRadius: 2)],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildRankItem(CategoryWeeklyStat stat, int index) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _getColorForId(stat.id, stat.isOverdueCategory).withOpacity(0.2),
        foregroundColor: _getColorForId(stat.id, stat.isOverdueCategory),
        child: stat.isOverdueCategory
          ? const Icon(Icons.warning, size: 18)
          : Text('${index + 1}'),
      ),
      title: Text(
        stat.displayName,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: stat.isOverdueCategory ? Colors.redAccent.shade700 : null,
        ),
      ),
      subtitle: Text('${stat.percentage.toStringAsFixed(1)}% del total'),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: stat.isOverdueCategory 
            ? Colors.redAccent.shade100.withOpacity(0.3)
            : Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          '${stat.count} tareas',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: stat.isOverdueCategory 
              ? Colors.redAccent.shade700
              : Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }

  List<Widget> _getSelectedSlivers({
    required List<CategoryWeeklyStat> stats,
    required List<UnassignedStat> unassignedStats,
    required List<OwnershipStat> ownershipStats,
    required Map<String, String> members,
  }) {
    if (_selectedViewIndex == 0) {
      if (stats.isEmpty) return [_buildEmptySliver('No hay tareas completadas para graficar.')];
      return [
        SliverToBoxAdapter(child: _buildPieChart(stats)),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 10, 20, 10),
            child: Text('Desglose Total', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildRankItem(stats[index], index),
            childCount: stats.length,
          ),
        ),
      ];
    } else if (_selectedViewIndex == 1) {
      if (unassignedStats.isEmpty) return [_buildEmptySliver('Nadie completó tareas sin asignar esta semana.')];
      return _buildInitiativeView(unassignedStats);
    } else {
      if (ownershipStats.isEmpty) return [_buildEmptySliver('Ninguna tarea asignada fue completada esta semana.')];
      return _buildSaviorsView(ownershipStats, members);
    }
  }

  Widget _buildEmptySliver(String message) {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.auto_graph_outlined, size: 70, color: Colors.grey),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildInitiativeView(List<UnassignedStat> unassignedStats) {
    double maxY = unassignedStats.fold(0, (max, stat) => stat.count > max ? stat.count.toDouble() : max);
    maxY = maxY + 1;

    return [
      const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 5),
          child: Text('Iniciativa Voluntaria', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ),
      const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Text('Tareas NO asignadas que completó cada integrante.', style: TextStyle(fontSize: 13, color: Colors.grey)),
        ),
      ),
      SliverToBoxAdapter(
        child: Container(
          height: 300,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: BarChart(
            BarChartData(
              maxY: maxY,
              alignment: BarChartAlignment.spaceEvenly,
              barTouchData: BarTouchData(enabled: false),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      if (value < 0 || value >= unassignedStats.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(unassignedStats[value.toInt()].displayName, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                      );
                    },
                    reservedSize: 40,
                  ),
                ),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    getTitlesWidget: (value, meta) {
                       if (value % 1 != 0) return const SizedBox.shrink();
                       return Text(value.toInt().toString(), style: const TextStyle(fontSize: 10));
                    }
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              gridData: const FlGridData(show: true, drawVerticalLine: false),
              barGroups: unassignedStats.asMap().entries.map((e) {
                final stat = e.value;
                return BarChartGroupData(
                  x: e.key,
                  barRods: [
                    BarChartRodData(
                      toY: stat.count.toDouble(),
                      color: _getColorForId(stat.uid, false),
                      width: 25,
                      borderRadius: BorderRadius.circular(4),
                    )
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildSaviorsView(List<OwnershipStat> ownershipStats, Map<String, String> members) {
    return [
      const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 5),
          child: Text('Rescatistas (Proporción 100%)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ),
      const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Text('De las tareas asignadas a X, ¿quién terminó completándolas?', style: TextStyle(fontSize: 13, color: Colors.grey)),
        ),
      ),
      SliverToBoxAdapter(
        child: Container(
          height: 350,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceEvenly,
              maxY: 100, 
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                   getTooltipItem: (group, groupIndex, rod, rodIndex) => null,
                )
              ),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      if (value < 0 || value >= ownershipStats.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text("De:\n" + ownershipStats[value.toInt()].ownerName, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                      );
                    },
                    reservedSize: 50,
                  ),
                ),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 35,
                    getTitlesWidget: (value, meta) {
                       return Text('${value.toInt()}%', style: const TextStyle(fontSize: 10));
                    }
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              gridData: const FlGridData(show: true, drawVerticalLine: false),
              barGroups: ownershipStats.asMap().entries.map((e) {
                final stat = e.value;
                final total = stat.totalAssignedAndCompleted;
                
                double currentY = 0;
                List<BarChartRodStackItem> stackItems = [];
                final sortedSolvers = stat.completedByCounts.entries.toList()
                     ..sort((a,b) => b.value.compareTo(a.value)); 
                     
                for (var solver in sortedSolvers) {
                   double p = (solver.value / total) * 100;
                   if (p > 0) {
                      stackItems.add(BarChartRodStackItem(
                         currentY, 
                         currentY + p, 
                         _getColorForId(solver.key, false)
                      ));
                      currentY += p;
                   }
                }
                
                return BarChartGroupData(
                  x: e.key,
                  barRods: [
                    BarChartRodData(
                      toY: 100, 
                      width: 35,
                      borderRadius: BorderRadius.circular(4),
                      rodStackItems: stackItems,
                      color: Colors.transparent,
                    )
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
           padding: const EdgeInsets.all(20),
           child: _buildSaviorsLegend(members),
        ),
      ),
    ];
  }
  
  Widget _buildSaviorsLegend(Map<String, String> members) {
      return Wrap(
        spacing: 12,
        runSpacing: 8,
        children: members.entries.map((e) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                   width: 12, height: 12, 
                   decoration: BoxDecoration(color: _getColorForId(e.key, false), shape: BoxShape.circle),
                ),
                const SizedBox(width: 4),
                Text(e.value, style: const TextStyle(fontSize: 11)),
              ]
            );
        }).toList()
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
