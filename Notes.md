Some thoughts about the Apple's Wallet App that can be applied to this app.
1.	You start “Add Card” in Wallet.
	2.	Wallet gets your card details:
	•	Camera/manual entry, or
	•	Tap-to-Add via NFC: some banks let you hold the physical card near the iPhone; Wallet reads a few EMV fields from the chip over NFC.
	3.	Apple sends the (encrypted) card data + device info to the card network’s token service (e.g., Visa VTS, Mastercard MDES, Amex, etc.) and your issuer.
	4.	The network/issuer tokenizes the card (creates a Device Primary Account Number — DPAN) and issues payment keys.
	5.	The DPAN + keys are delivered over-the-air into the iPhone’s Secure Element (eSE).
	6.	You complete identity verification (bank app/SMS/call).
	7.	Card is ready. Payments use Face ID/Touch ID (CDCVM) and generate a one-time EMV cryptogram per transaction. Merchants see your token (DPAN), not the real PAN.

Technologies under the hood
	•	NFC (ISO/IEC 14443, reader mode) – used for Tap-to-Add from the physical card (when supported by the issuer).
	•	EMV specs – card data layout & EMV contactless cryptography/transaction model.
	•	Tokenization – network token service (VTS/MDES/etc.) creates a device-specific token.
	•	Secure Element (embedded, hardware) – stores DPAN + payment keys; runs payment applets.
(This is not the Secure Enclave—different chips; Secure Enclave handles biometrics/keys for auth.)
	•	GlobalPlatform (secure channel, provisioning) – used to securely load credentials into the SE.
	•	CDCVM (Consumer Device Cardholder Verification Method) – Face ID/Touch ID/passcode verification on device.
	•	TLS + device attestation – for provisioning requests to Apple/issuer/network.

Apple frameworks / “packages” you’ll actually touch as a developer
	•	PassKit.framework (Wallet/Apple Pay)
	•	PKAddPaymentPassViewController – for in-app provisioning (issuer apps add their card to Wallet).
	•	Apple Pay merchant side: PKPaymentAuthorizationController to take payments in your app.
	•	You do not use CoreNFC to read payment chips. Apple does NFC EMV reading with private system entitlements; third-party apps can’t read EMV payment applets.
	•	Optional issuer-side SDKs: banks often integrate network SDKs/APIs (VTS/MDES) or a TSM to handle verification & activation.

Notes & gotchas
	•	Tap-to-Add via NFC only appears for participating issuers; otherwise you’ll see camera/manual entry.
	•	Each device gets a different token; removing the card wipes the token from that device’s Secure Element.
	•	None of the sensitive payment keys are accessible to apps or iOS; they live and operate inside the SE.
