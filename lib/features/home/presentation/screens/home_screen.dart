import 'package:flutter/material.dart';
import '../../../auth/data/auth_repository.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authRepo = AuthRepository();
    final user = authRepo.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Coop - Inicio'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => authRepo.signOut(),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.verified_user, size: 64, color: Colors.green),
            const SizedBox(height: 16),
            Text(
              '¡Bienvenido!',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text('Usuario: ${user?.email ?? "Anónimo"}'),
          ],
        ),
      ),
    );
  }
}