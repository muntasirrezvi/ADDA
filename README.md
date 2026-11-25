# Adda: live backend and admin console

This folder holds the real, deployable parts of Adda:

| Folder | What it is |
|---|---|
| `supabase/migrations/` | Database: tables, security rules, all coin/gift/payment logic, storage buckets, starting data |
| `supabase/functions/` | Server APIs: Agora tokens (voice rooms and 1-to-1 calls), SSLCommerz (bKash, Nagad, Rocket, Visa, Mastercard), Google Play purchase check, phone login, push notifications |
| `admin/` | Owner console (Next.js) for you, your moderators and your coin agents. Deploys free on Vercel. |
| `app/` | The Flutter app for Android and iOS. See `app/README.md`. |
| `.github/workflows/build.yml` | On every push to GitHub: tests the database, builds the console, and builds the Android APK |
| `supabase/tests/smoke.sql` | The test script the database was checked with |


---

## 1. Accounts you need (all have free tiers)

| Service | Used for | Free tier (check current limits) |
|---|---|---|
| Supabase | Database, sign-in, file storage, realtime chat, APIs | 500 MB database, 1 GB files. A free project pauses after 7 days with no activity. |
| Agora.io | Voice rooms, voice calls and video calls | 10,000 minutes a month |
| SSLCommerz | bKash, Nagad, Rocket, Visa, Mastercard | Sandbox is free. Live needs a merchant account (trade licence or NID). They charge a fee per payment. |
| Google Play Console | Publish the app and sell coins in-app | One-time $25 |
| Firebase | Push notifications (FCM) | Free |
| Brevo or Resend | Sign-up confirmation emails | Brevo about 300 a day; Resend about 3,000 a month |
| Vercel | Hosts the admin console | Free |

**Never paste keys or passwords into a chat, an email, or the code.** They go into Supabase secrets (step 3) or Vercel environment variables (step 5).

---

## 2. Set up the database

1. Create a project at supabase.com. Pick the region closest to most users (Singapore suits Bangladesh and Asia Pacific; Frankfurt or Mumbai for the Middle East).
2. Install the Supabase CLI, then from this folder run:
   ```bash
   supabase login
   supabase link --project-ref YOUR_PROJECT_REF
   supabase db push
   ```
   This creates every table, rule and function, plus the starting coin packs, gifts, cover templates, themes and banners.
3. **Make yourself the owner.**
   - Create your account: Supabase dashboard, then Authentication, Users, Add user (email and password).
   - In the SQL editor, run:
     ```sql
     update profiles set role = 'admin' where id = (select id from auth.users where email = 'you@example.com');
     ```
   - Use `moderator` for staff who handle reports and users. Moderators cannot touch money or settings.
4. **Set up sign-in.**
   - Go to Authentication, then Providers. Keep **Email** on and turn on "Confirm email".
   - Go to Authentication, then SMTP. Add Brevo or Resend; Supabase's built-in email is only for testing.
   - Phone OTP by SMS always costs money (Twilio and similar), so it is off for now. Sign-up collects email and phone (the phone is required). After that, users sign in with **email + password** or **phone + password**; the phone route uses the `login-phone` function. Turn on SMS verification later if you want phone numbers proven.

## 3. Deploy the server functions

```bash
supabase functions deploy agora-token
supabase functions deploy pay-create
supabase functions deploy pay-google-verify
supabase functions deploy pay-sslcommerz-ipn --no-verify-jwt
supabase functions deploy login-phone --no-verify-jwt
supabase functions deploy push --no-verify-jwt
```

Then add the secrets in the dashboard (Edge Functions, then Secrets). Supabase already provides `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY`.

| Secret | Where to get it |
|---|---|
| `AGORA_APP_ID`, `AGORA_APP_CERTIFICATE` | Agora console: create a project in "Secured mode (APP ID + Token)" |
| `SSLCOMMERZ_STORE_ID`, `SSLCOMMERZ_STORE_PASSWORD` | SSLCommerz sandbox sign-up (developer.sslcommerz.com) and later the live merchant panel |
| `SSLCOMMERZ_LIVE` | `false` while testing, `true` when SSLCommerz approves you for live |
| `APP_RETURN_URL` | Where the payment page sends users back, e.g. `adda://wallet` |
| `ANDROID_PACKAGE_NAME` | Your app id, e.g. `app.adda.voice` |
| `GOOGLE_SERVICE_ACCOUNT_JSON` | Google Cloud: create a service account and a JSON key. In Play Console, go to Users and permissions, invite that email, and give it "View financial data" and "Manage orders". Paste the whole JSON as the secret value. |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | Firebase: Project settings, Service accounts, Generate new private key |
| `PUSH_WEBHOOK_SECRET` | Any long random string you make up |

**Push notifications.** Go to Database, then Webhooks, and create a webhook:
- Table `notifications`, event Insert.
- Type: Supabase Edge Function, function `push`.
- HTTP header `x-webhook-secret` set to your `PUSH_WEBHOOK_SECRET`.

**SSLCommerz.** In the merchant panel, set the IPN URL to `https://YOUR_PROJECT.supabase.co/functions/v1/pay-sslcommerz-ipn?r=ipn`.

## 4. How the payment flows work

**Agent top-ups (the main way; switched on by default)**
1. In the console, open **Coin agents**. Pick 4 or 5 agents, turn on **Receives top-ups**, add their bKash/Nagad/Rocket numbers, and give them coin stock.
2. In the app, a user taps a pack and then bKash (for example). They see one agent's number, the exact amount, and a 30-minute timer. Orders go to the agent with enough stock and the fewest orders waiting.
3. The user sends the money and enters the TrxID (and can add a screenshot).
4. The agent sees it at once on **Top-up orders**, with a sound. They check their bKash statement, then tap **Payment received**. The coins move from that agent's stock to the user, and the user is notified.
5. You see every order and every agent's stock and sales. You can approve or reject any order yourself, or move it to another agent.
6. Safety: the same TrxID can never be used twice, an agent can only approve orders assigned to them, and everything is logged.

Switch other methods on or off in **Settings**: `pay_agent_enabled`, `pay_sslcommerz_enabled`, `pay_play_enabled`.


**bKash / Nagad / Rocket / cards (SSLCommerz)**
1. The app calls `pay-create` with `{ pack: "p10" }`. The database works out the price, including the user's discount (up to 20%), and records a pending payment.
2. The app opens the returned `url` in a web view, and the user pays there.
3. SSLCommerz calls `pay-sslcommerz-ipn`. The function checks the payment with SSLCommerz's validation API and checks that the amount, currency and transaction match the pending payment. Only then are the coins added. A payment can never be counted twice.
4. If SSLCommerz flags a card as high risk, the payment waits under Payments in the console, where you approve it by hand.

**Google Play**
1. The app buys product `coins_5m` (and so on), passing the user's id as `obfuscatedAccountId`.
2. The app sends `{ productId, purchaseToken }` to `pay-google-verify`. Google confirms the purchase, the coins are added once, and the purchase is consumed so it can be bought again.
3. Create the same product IDs in Play Console (Monetize, then In-app products). Play Console sets those prices; the 20% discount applies to SSLCommerz only.

**Coin agents.** You give an agent a coin stock from the console. The agent takes cash from a user (bKash and so on) and sends coins with `agent_sell`. Every sale is logged.

## 5. Deploy the admin console

1. Push this folder to GitHub.
2. Create a project at vercel.com: New Project, import the repo, set the **Root directory** to `admin`.
3. Add two environment variables: `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` (from Supabase, Project Settings, API). The anon key is safe in a browser, because every admin action is checked in the database against your role.
4. Deploy, then sign in with your admin email or phone.

To run it locally: `cd admin && cp .env.example .env.local`, fill it in, then `npm install && npm run dev`.

### What the console manages
- **Dashboard.** Revenue, payments, sign-ups, live rooms, coins gifted, and a to-do list of open reports, ID checks and payouts.
- **Rooms & homepage.** Change any room's cover image or cover template, pin rooms to the top of the home screen and set their order, change the theme, and suspend or close rooms.
- **Banners & layout.** The home carousel (images, text, button action, schedule) and the order of the home screen sections.
- **Covers & themes.** The cover templates creators choose from when making a room (upload or replace images, hide, set a price), plus free and premium room themes.
- **Users.** Search by name, ID, email or phone. Add or remove coins (a reason is required), ban or unban, change role (user, host, agent, moderator, admin), and see coin history.
- **Payments.** Every SSLCommerz and Google Play payment. Approve held payments and mark refunds.
- **Coin ledger.** Every coin and diamond movement.
- **Gifts.** Price, tier, icon, full-screen animation file (Lottie JSON, WebP or MP4), event dates.
- **Coin packs.** Coins, USD, BDT, pack discount, Google Play product ID.
- **Coin agents.** Agent stock and sales.
- **Reports.** Warn, ban, suspend a room, remove a reel, or dismiss.
- **Verifications.** Host ID checks. Photos are private and shown through 10-minute links.
- **Host payouts.** Approve, mark paid, or reject (rejecting returns the diamonds).
- **Reels.** Watch, remove or restore.
- **Music.** Tracks for the reel creator. Only upload music you have the rights to.
- **Broadcast.** Send a notification to everyone.
- **Settings.** Rates, welcome bonus, minimum bet, game loss limit, blocked words, maintenance mode, minimum app version.
- **Audit log.** Every admin action, with who did it.

## 6. How rooms get their homepage image

- When creating a room, the creator either uploads a cover photo (to `room-covers/<their user id>/…`) or picks one of the cover templates. The database rejects images from someone else's folder and templates that are hidden or paid.
- The owner can change the name, cover, template and theme later.
- You can override any of this from the console. Only admins can pin a room, set its order or suspend it.
- The app's home screen calls `home_rooms()`, which returns pinned rooms first (in your order), then live rooms by activity. `cover_image` is already resolved: the uploaded photo if there is one, otherwise the template image.

## 7. API list for the app

Everything below is called with the user's sign-in token.

| Call | Purpose |
|---|---|
| `auth.signUp({ email, password, options: { data: { username, phone, country } } })` | Sign up. A profile, a wallet and the welcome bonus are created automatically. |
| `auth.signInWithPassword({ email, password })` or `functions.invoke('login-phone', { phone, password })` | Sign in |
| `rpc('home_feed')`, `rpc('home_rooms', { p_tab: 'hot' \| 'new' \| 'following' })` | Home screen |
| `rpc('create_room', …)`, `rpc('join_room', { p_room, p_password })`, `rpc('take_seat')`, `rpc('leave_seat')`, `rpc('leave_room')` | Rooms |
| `rpc('host_seat_action', { p_action: 'lock' \| 'unlock' \| 'mute' \| 'unmute' \| 'remove' })`, `rpc('kick_from_room')`, `rpc('set_room_admin')` | Host tools |
| `functions.invoke('agora-token', { kind: 'room' \| 'call', id })` | Join Agora voice or video. Ask again after taking or leaving a seat. |
| `rpc('start_call', { p_callee, p_type: 'audio' \| 'video' })`, `rpc('update_call', { p_status: 'active' \| 'declined' \| 'ended' })` | 1-to-1 calls. The call log is written to the inbox automatically. |
| `rpc('send_gift', { p_room, p_receivers, p_gift, p_qty })` | Gifts (quantity 1, 10 or 99). Returns the new balance and whether the user levelled up. |
| `rpc('my_coin_packs')`, `functions.invoke('pay-create')`, `functions.invoke('pay-google-verify')` | Top-up |
| `rpc('toggle_reel_like')`, `rpc('donate_reel')`, `rpc('view_reel')` | Reels. Upload the video to `reels/<user id>/…`, then insert into `reels`. |
| `rpc('daily_checkin')`, `rpc('exchange_diamonds')`, `rpc('request_verification')`, `rpc('request_payout')`, `rpc('buy_theme')` | Rewards and earnings |
| `rpc('delete_my_account')` | Required by Apple and Google |
| Realtime on `room_messages`, `room_seats`, `gift_events`, `direct_messages`, `calls`, `notifications`, `wallets`, `topup_orders` | Live chat, seats, gift animations, incoming calls, balance, top-up status |
| `rpc('topup_methods')`, `rpc('create_topup_order')`, `rpc('submit_topup_proof')`, `rpc('cancel_topup_order')` | Agent top-ups |

## 8. Safety and money rules built into the database
- The app cannot change a balance, price or level directly. Every coin movement goes through a function and is written to the ledger.
- Users can read only their own wallet, payments, email and phone. Room passwords are stored hashed and are never readable.
- Links are blocked in chats, and blocked words are masked.
- Blocked users cannot message, call or gift the person who blocked them.
- Every admin action that touches money, users, rooms or settings is recorded in the audit log.
- **Economy guard.** A gift pays the host `diamond_rate` (0.5) diamonds per coin, and diamonds exchange back at `diamond_to_coins` (1). Keep `diamond_rate × diamond_to_coins` below 1. If it reaches 1 or more, two accounts can gift each other in a loop and create coins out of nothing.

## 9. Things to decide before launch
- **Lucky games with purchased coins.** Google Play, Apple and payment providers treat games where bought coins can be bet as gambling. That can get the app rejected or the SSLCommerz account closed. Safer options:
  - Launch without the Lucky games, or
  - Let them use only free coins earned from check-ins and tasks.

  Settle game results on the server before turning them on (the current games are prototype-only).
- **Storage.** The free 1 GB fills quickly with videos. Once reels take off, move them to Cloudflare R2 (10 GB free, no download fees) or a paid Supabase plan.
- **Privacy policy and terms.** Both stores require public pages for these.
