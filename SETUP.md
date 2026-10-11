# DomyAI Server: guida rapida

App Flutter che avvia sul telefono un server compatibile con l'API OpenAI
(`/v1/models`, `/v1/chat/completions`, streaming incluso), con llama.cpp come motore.

## 1. Creare il progetto
```
flutter create --org it.domyk22 --project-name domyai_server domyai_server
```
Copia dentro la cartella creata `lib/` e `pubspec.yaml` di questo pacchetto (sovrascrivendo), poi:
```
flutter pub get
```

## 2. Configurazione Android
In `android/app/src/main/AndroidManifest.xml`, dentro `<manifest>` e prima di `<application>`:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
```
In `android/app/build.gradle.kts`, dentro `defaultConfig`:
```kotlin
ndk { abiFilters += listOf("arm64-v8a") }
```

## 3. Librerie di llama.cpp (passo manuale)
Compila llama.cpp come libreria condivisa per arm64 con l'Android NDK:
```
cmake -B build-android \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-29 \
  -DBUILD_SHARED_LIBS=ON -DGGML_OPENMP=OFF
cmake --build build-android --config Release -j8
```
Copia **tutti** i file `.so` generati (libllama.so, libggml*.so) in
`android/app/src/main/jniLibs/arm64-v8a/`.

Se `lib/engine.dart` non compila, l'API di `llama_cpp_dart` è cambiata:
guarda il README della versione installata e adatta solo `LlamaEngine`.

## 4. Provare
1. `flutter run` con il telefono in debug USB.
2. Attiva **Modalità test** e avvia: dal PC apri `http://IP_TELEFONO:8080/v1/models`.
3. Copia un modello `.gguf` (es. Qwen2.5-Coder 1.5B Q4_K_M) nella cartella mostrata dall'app,
   premi Aggiorna, scegli il modello, spegni la modalità test e avvia.

## 5. Collegare i client
**VS Code (Continue)**, `config.yaml`:
```yaml
models:
  - name: DomyAI
    provider: openai
    model: domyai
    apiBase: http://IP_TELEFONO:8080/v1
    apiKey: la-tua-key-o-none
```
**Sito web**: carica `domyai-chat.html` sul tuo hosting. Se il sito è in HTTPS, il browser
blocca le chiamate verso `http://`: serve un indirizzo HTTPS verso il telefono
(Cloudflare Tunnel, Tailscale Funnel o ngrok). Se esponi il server su internet, imposta sempre una API key.

## Limiti della v1
- Una richiesta alla volta (le altre ricevono 429).
- L'inferenza gira sul thread principale: l'interfaccia dell'app può scattare mentre genera.
- Contesto di 2048 token; il formato del prompt è ChatML (Qwen). Per altri modelli cambia `_prompt` in `server.dart`.
- Schermo tenuto acceso durante l'uso (wakelock); disattiva l'ottimizzazione batteria per l'app.

## Scorciatoia: APK compilato da GitHub
Il file `.github/workflows/build-apk.yml` compila tutto (llama.cpp incluso) senza installare nulla in locale:
1. Crea un repository GitHub e carica il contenuto di questa cartella (ramo `main`).
2. Scheda **Actions** > **Build APK** > **Run workflow**.
3. A fine lavoro (10-20 minuti) scarica `domyai-server-apk` dagli Artifacts, estrai `app-release.apk` e installalo sul telefono.
Se il lavoro fallisce, copia l'errore dal log: di solito riguarda `lib/engine.dart` (API di llama_cpp_dart).
