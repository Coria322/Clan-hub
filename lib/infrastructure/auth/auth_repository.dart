import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);
final googleSignInProvider = Provider<GoogleSignIn>((ref) => GoogleSignIn());
final firestoreProvider = Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(firebaseAuthProvider),
    ref.watch(googleSignInProvider),
    ref.watch(firestoreProvider),
  );
});

final authStateChangesProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

class AuthRepository {
  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;
  final FirebaseFirestore _firestore;

  AuthRepository(this._auth, this._googleSignIn, this._firestore);

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<void> _createUserProfile(User user, String displayName) async {
    // Actualizar el perfil de Firebase Auth con el displayName (para que currentUser.displayName siempre esté disponible)
    if (user.displayName == null || user.displayName!.isEmpty) {
      await user.updateDisplayName(displayName);
    }

    final userDoc = _firestore.collection('users').doc(user.uid);
    final docSnapshot = await userDoc.get();

    if (!docSnapshot.exists) {
      await userDoc.set({
        'uid': user.uid,
        'displayName': displayName,
        'email': user.email,
        'photoUrl': user.photoURL,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      // Si el doc existe pero no tiene displayName, actualizarlo
      final data = docSnapshot.data() ?? {};
      if (data['displayName'] == null || (data['displayName'] as String).isEmpty) {
        await userDoc.update({'displayName': displayName});
      }
    }
  }

  Future<UserCredential> signInWithEmail(String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential') {
        throw AuthException('Correo o contraseña incorrectos.');
      }
      throw AuthException(e.message ?? 'Error al iniciar sesión.');
    } catch (e) {
      throw AuthException('Error inesperado al iniciar sesión: $e');
    }
  }

  Future<UserCredential> registerWithEmail(String email, String password, String displayName) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      if (credential.user != null) {
        await _createUserProfile(credential.user!, displayName);
      }
      return credential;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        throw AuthException('Este correo ya tiene una cuenta.');
      }
      throw AuthException(e.message ?? 'Error al registrarse.');
    } catch (e) {
      throw AuthException('Error inesperado al registrarse: $e');
    }
  }

  Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null; // Cancelado por el usuario

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      if (userCredential.user != null) {
        await _createUserProfile(userCredential.user!, userCredential.user!.displayName ?? 'Usuario');
      }
      return userCredential;
    } catch (e) {
      throw AuthException('Error al iniciar sesión con Google.');
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        throw AuthException('No existe una cuenta registrada con este correo.');
      }
      throw AuthException(e.message ?? 'Error al enviar el correo de recuperación.');
    } catch (e) {
      throw AuthException('Error inesperado: $e');
    }
  }

  Future<void> updatePassword(String newPassword) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw AuthException('No hay un usuario autenticado.');
      await user.updatePassword(newPassword.trim());
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        throw AuthException('Por seguridad, esta acción requiere que hayas iniciado sesión recientemente. Por favor, cierra sesión e inicia nuevamente.');
      }
      throw AuthException(e.message ?? 'Error al cambiar la contraseña.');
    } catch (e) {
      throw AuthException('Error inesperado: $e');
    }
  }
}
