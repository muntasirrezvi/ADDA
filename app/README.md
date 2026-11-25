# Adda mobile app (Flutter)

Android and iOS app for Adda. It talks only to your Supabase project and the server functions in `../supabase`.

## Build on your computer
1. Install Flutter (stable) and Android Studio: https://docs.flutter.dev/get-started/install
2. In this folder:
   ```bash
   bash tool/setup.sh          # first time: creates android/ and ios/ and adds permissions
   flutter pub get
   flutter run --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
   ```
3. Release APK for testing on phones:
   ```bash
   flutter build apk --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
   ```
   The file is in `build/app/outputs/flutter-apk/app-release.apk`.

The anon key is public by design. Never put the service-role key, Agora certificate or payment passwords in the app.

## Or let GitHub build it
Push the repo to GitHub, add the repository secrets `SUPABASE_URL` and `SUPABASE_ANON_KEY` (Settings → Secrets and variables → Actions). Every push builds an APK; download it from the Actions tab → the run → Artifacts.

## What is in the app
| Screen | What it does |
|---|---|
| Sign up / sign in | Sign-up asks for username, email, phone, country and password. Sign in with email or phone plus password. |
| Rooms (home) | Banners, upcoming events, Popular / New / Following rooms. Covers show the uploaded photo or the template. |
| Voice room | Agora voice, seats (host + 8/12/16), speaking glow, mute, host tools (lock, mute, remove, kick, room admins), chat, full-screen gift animations, follow, events, edit cover/theme, close room |
| Create room | Name, topic, language, seats, cover photo upload or template, free or premium theme, optional password |
| Wallet | Coin packs with personal discount. Pay an agent by bKash, Nagad, Rocket, Upay, bank or USDT; SSLCommerz checkout and Google Play when you switch them on in Settings. Diamond exchange, top-up history. |
| Reels | Vertical feed, likes, comments, coin gifts to creators, music plays with the video |
| Make a reel | Camera recording up to 30 s with a trending track playing, preview, caption, upload |
| Inbox | Conversations, live chat, read ticks, notifications |
| Calls | 1-to-1 voice and video calls (Agora), incoming call screen, call log in the chat |
| Profile | Cover, avatar (photo or illustrated), level, followers, reels; follow, message, call, block, report |
| Me | Edit profile, wallet, host earnings and withdrawals, identity verification, settings, sign out, delete account |

## Not in this version
- **Push notifications when the app is closed.** Calls and messages arrive while the app is open. Adding Firebase (`firebase_messaging`) is the next step; the `push` server function is already written.
- **Lucky games.** They are left out on purpose until the gambling question is settled (see the launch checklist).
- **Arabic right-to-left layout.** Not included, as you decided.
