import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_tokens.dart';
import '../providers/auth_provider.dart';
import 'pos/pos_home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usuarioController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _loadRememberedCredentials();
  }

  Future<void> _loadRememberedCredentials() async {
    final remembered = await context.read<AuthProvider>().getRememberedCredentials();
    if (remembered == null || !mounted) return;

    setState(() {
      _usuarioController.text = remembered['usuario'] as String? ?? '';
      _passwordController.text = remembered['password'] as String? ?? '';
      _rememberMe = true;
    });
  }

  @override
  void dispose() {
    _usuarioController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final success = await auth.login(
      _usuarioController.text.trim(),
      _passwordController.text,
      rememberMe: _rememberMe,
    );

    TextInput.finishAutofillContext();

    if (success && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const POSHomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final colors = context.colors;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: colors.accent,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    child: Center(
                      child: Image.asset(
                        'assets/branding/logo_mark.png',
                        width: 32,
                        height: 32,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Cuadre de Caja',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: colors.accent,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Punto de Venta',
                    style: TextStyle(
                      fontSize: 15,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 48),

                  AutofillGroup(
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _usuarioController,
                          decoration: InputDecoration(
                            labelText: 'Usuario',
                            prefixIcon: const Icon(Icons.person),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                          ),
                          validator: (v) => v == null || v.isEmpty
                              ? 'Ingresa tu usuario'
                              : null,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.username],
                        ),
                        const SizedBox(height: 16),

                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            prefixIcon: const Icon(Icons.lock),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                          ),
                          validator: (v) => v == null || v.isEmpty
                              ? 'Ingresa tu contraseña'
                              : null,
                          autofillHints: const [AutofillHints.password],
                          onFieldSubmitted: (_) => _login(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),

                  Row(
                    children: [
                      Checkbox(
                        value: _rememberMe,
                        activeColor: colors.accent,
                        onChanged: (v) =>
                            setState(() => _rememberMe = v ?? false),
                      ),
                      GestureDetector(
                        onTap: () =>
                            setState(() => _rememberMe = !_rememberMe),
                        child: Text(
                          'Recordarme',
                          style: TextStyle(color: colors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (auth.errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: colors.negativeWash,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: colors.negative),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              auth.errorMessage!,
                              style: TextStyle(color: colors.negative),
                            ),
                          ),
                        ],
                      ),
                    ),

                  SizedBox(
                    width: double.infinity,
                    height: AppTapTarget.comfortable,
                    child: ElevatedButton(
                      onPressed:
                          auth.status == AuthStatus.loading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.accent,
                        foregroundColor: colors.onAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                      child: auth.status == AuthStatus.loading
                          ? SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: colors.onAccent,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Iniciar Sesión',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
