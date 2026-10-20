import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import '../widgets/common.dart';

class FarePage extends StatelessWidget {
  const FarePage({super.key});

  Future<void> _edit(
    BuildContext context,
    double defaultFare,
    double roundFare,
  ) async {
    final defaultController = TextEditingController(
      text: defaultFare.toStringAsFixed(2),
    );
    final roundController = TextEditingController(
      text: roundFare.toStringAsFixed(2),
    );
    String? error;
    bool saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refresh) => AlertDialog(
          title: const Text('Fare settings'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Default fare applies when the vehicle reaches the passenger\'s destination in its current direction. Round-trip fare applies when the vehicle must pass an endpoint and reverse direction before reaching the destination.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: defaultController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Default Fare',
                    prefixText: 'PHP ',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: roundController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Round Trip Fare',
                    prefixText: 'PHP ',
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final normal = double.tryParse(
                        defaultController.text.trim(),
                      );
                      final round = double.tryParse(
                        roundController.text.trim(),
                      );
                      if (normal == null ||
                          round == null ||
                          !normal.isFinite ||
                          !round.isFinite ||
                          normal <= 0 ||
                          round <= 0) {
                        refresh(
                          () =>
                              error = 'Enter a positive amount for both fares.',
                        );
                        return;
                      }
                      refresh(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        await FirebaseService.instance.updateGlobalFares(
                          defaultFare: normal,
                          roundTripFare: round,
                        );
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (exception) {
                        if (dialogContext.mounted) {
                          refresh(() {
                            saving = false;
                            error = 'Could not save fares: $exception';
                          });
                        }
                      }
                    },
              child: Text(saving ? 'Saving...' : 'Save'),
            ),
          ],
        ),
      ),
    );
    defaultController.dispose();
    roundController.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: FirebaseService.instance.db
        .collection('settings')
        .doc('fares')
        .snapshots(),
    builder: (context, snapshot) {
      final data = snapshot.data?.data();
      final defaultFare =
          (data?['defaultFare'] as num?)?.toDouble() ??
          (data?['wholeTripFare'] as num?)?.toDouble();
      final roundFare = (data?['roundTripFare'] as num?)?.toDouble();
      return SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageIntro(
              title: 'Fare settings',
              subtitle:
                  'Universal fares based on the vehicle\'s current route direction.',
              action: FilledButton.icon(
                onPressed: () =>
                    _edit(context, defaultFare ?? 0, roundFare ?? 0),
                icon: const Icon(Icons.edit),
                label: const Text('Edit fares'),
              ),
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _FareCard(
                  'DEFAULT FARE',
                  defaultFare,
                  'The fare for a trip that reaches the passenger\'s destination in the vehicle\'s current direction.',
                ),
                _FareCard(
                  'ROUND TRIP FARE',
                  roundFare,
                  'The fare for a trip that passes a route endpoint before reaching the passenger\'s destination after the vehicle reverses direction.',
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'The total booking fare is the selected fare multiplied by passenger count.',
            ),
            if (snapshot.hasError)
              Text('Could not load fare settings: ${snapshot.error}'),
          ],
        ),
      );
    },
  );
}

class _FareCard extends StatelessWidget {
  const _FareCard(this.title, this.amount, this.explanation);
  final String title;
  final double? amount;
  final String explanation;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 320,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              amount == null ? 'Not set' : 'PHP ${amount!.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(explanation),
          ],
        ),
      ),
    ),
  );
}
