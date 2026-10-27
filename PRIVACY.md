# Privacy

PlainTranslate has no account system, advertising, analytics, crash-upload
service or translation history. No PlainTranslate server receives your text.

## Apple translation

Apple is the default translation engine. Translation uses Apple's on-device
Translation framework. Language models may need an initial download from Apple;
the system requests permission when needed. Supported languages depend on the
installed macOS version and Apple framework support. PlainTranslate does not
silently fall back to Google when local translation is unavailable.

## Google Cloud translation

Google is optional and requires your own Cloud Translation API key. When you
select Google and request a translation, PlainTranslate sends the prepared input
text, source language (unless automatic), and target language directly to the
official Google Cloud Translation Basic v2 HTTPS endpoint. If PDF cleanup is
enabled, the submitted text includes that cleanup.

- Your key is kept in your local macOS Keychain, under the independent service
  `com.chyo.plaintranslate.translation.google`.
- Keys are not saved in ordinary preferences, source code, translation history,
  logs, or exported settings. The app never uses a shared developer API key.
- Requests use the key in an HTTP header, not a URL query parameter. Redirects
  are refused. Requests use an ephemeral network session without cookies,
  credential storage or a response cache.
- Errors do not display raw Google server responses, keys, or submitted text.
- Google may charge the GCP project associated with your key. Restrict the key
  to Cloud Translation API and manage quotas and billing in Google Cloud.

Google's service terms and privacy documentation apply to text you choose to
send to Google. See [Google Cloud Translation data usage](https://docs.cloud.google.com/translate/data-usage).

## Clipboard and shortcuts

The global double-copy shortcut is **off by default**, so installing the app
does not compete with another translator. You can use the editor without
granting Accessibility access. Enabling global double-copy requires macOS
Accessibility permission; the app observes key events to recognize two copies
in a short interval and does not consume or rewrite the copy shortcut.

The app reads the clipboard when you explicitly paste or invoke translation
through the shortcut. It does not create a clipboard history. Recognized
protected clipboard types are refused; not every application marks sensitive
content, so check your selected text before choosing a cloud engine. Copying a
translation places the result on the system clipboard, which other clipboard
utilities may read.

## Local settings and usage estimates

The app saves interface preferences, selected engine, speech preferences,
aggregate monthly Google submission counters, and whether a usage reminder has
been shown. It does not persist the translation input or result.

Monthly counters use the Hong Kong calendar month. They count submitted Unicode
code points, including whitespace, and submission attempts. Failed requests or
requests cancelled after submission remain in the estimate; explicit retries
count again. Apple translations do not count.

These counters only cover this installation of PlainTranslate since counting
began. They do not synchronize with Vorssaint, other apps, other computers,
Google's billing meter, or other use of the same API key. The 90% reminder uses
a 500,000-character reference allowance, is not a spending cap, and cannot
prevent Google charges. Check actual current allowance, quotas and charges in
your own Google Cloud project.

## Speech

Read-aloud uses the macOS speech synthesizer and installed system voices. Voice
downloads are managed by macOS. The app does not record your microphone or send
text to an additional speech service.

## Removal

Removing the app does not automatically revoke a Google API key or delete a
Keychain item. Use **Remove key** in the app before uninstalling if you want the
saved credential removed, and revoke the key in Google Cloud if no longer needed.
PlainTranslate's bundle identity and settings are separate from Vorssaint.
