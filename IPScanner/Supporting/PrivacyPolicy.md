# INFORMATIVA SULLA PRIVACY

**Ultimo aggiornamento:** 17 agosto 2026

## INTRODUZIONE

Questa Informativa sulla Privacy (di seguito "Informativa") descrive come i dati personali degli utenti (di seguito "Utente" o "Lei") vengono raccolti, utilizzati, trattati e protetti in relazione all'utilizzo dell'applicazione mobile **IPScanner** (di seguito "Applicazione").

**Titolare del Trattamento:**
Alain S. M. Lima
Sede legale: Palermo, Italia
Email: support@aldeveloping.it

Il Titolare non ha nominato un Data Protection Officer (DPO), non ricorrendo i presupposti di cui all'articolo 37 del Regolamento (UE) 2016/679 (GDPR). Per qualsiasi questione relativa al trattamento dei dati personali, l'Utente può contattare il Titolare all'indirizzo email sopra indicato.

La presente Informativa è resa ai sensi dell'articolo 13 del Regolamento (UE) 2016/679 (di seguito "GDPR") e, ove applicabile, del D.Lgs. 196/2003 (Codice in materia di protezione dei dati personali) e del California Consumer Privacy Act (CCPA) per i residenti in California, USA.

## 1. DATI PERSONALI TRATTATI

### 1.1 Dati trattati localmente sul dispositivo (NON trasmessi)

L'Applicazione è uno scanner di rete locale: tutte le scansioni vengono eseguite **interamente sul dispositivo** dell'Utente. I dati rilevati vengono salvati localmente sul dispositivo stesso e **non vengono trasmessi al Titolare né a server esterni**. Questi includono:

- Indirizzi IP, indirizzi MAC, hostname e produttori dei dispositivi rilevati sulla rete locale;
- Risultati delle scansioni delle porte e dello stato dei dispositivi (es. Wake-on-LAN);
- Cronologia delle scansioni e dati di esportazione (CSV/JSON);
- Personalizzazioni effettuate dall'Utente: nomi personalizzati, icone e lista dei dispositivi fidati (whitelist).

### 1.2 Dati raccolti automaticamente (SOLO se Crashlytics è attivo)

L'Applicazione può integrare **Firebase Crashlytics** (Google LLC) per la segnalazione degli errori e dei crash. Tale integrazione è **opzionale**: viene attivata dal Titolare solo nelle build che includono il file di configurazione Google (`GoogleService-Info.plist`). Quando attiva, possono essere raccolti:

- Identificativo anonimo di installazione (App Instance ID) — **NON** è l'identificativo pubblicitario Apple IDFA;
- Tipo e modello del dispositivo, versione del sistema operativo e versione dell'applicazione;
- Report di crash ed errori dell'applicazione (Crashlytics).

**L'Applicazione NON raccoglie:**
- Account, nome, email o dati di autenticazione (nessuna registrazione richiesta);
- Identificativo pubblicitario (IDFA/AAID);
- Dati di pagamento (l'Applicazione è gratuita e non contiene acquisti in-app);
- Dati di localizzazione precisi;
- Dati di navigazione web o attività di altre app;
- Contenuti personali dell'Utente (documenti, foto, ecc.).

### 1.3 Autorizzazioni di sistema richieste

L'Applicazione può richiedere le seguenti autorizzazioni; ciascuna può essere revocata in qualsiasi momento dall'Utente tramite le impostazioni del dispositivo:

| Autorizzazione | Finalità | Obbligatoria? |
|---|---|---|
| **Rete Locale** | Rilevamento e scansione dei dispositivi della rete | SÌ (funzionalità principale) |
| **Notifiche** | Avvisi per i nuovi dispositivi rilevati | NO |

## 2. FINALITÀ DEL TRATTAMENTO E BASE GIURIDICA

### 2.1 Finalità del Trattamento

I dati personali sono trattati per le seguenti finalità:

**A. Erogazione del Servizio** (base giuridica: esecuzione del contratto — Art. 6(1)(b) GDPR)
- Fornire le funzionalità dell'Applicazione (scansione LAN, dettagli dispositivi, strumenti Ping/Porte/Wake-on-LAN, cronologia, esportazione, trasferimento peer-to-peer);
- Fornire assistenza tecnica e supporto.

**B. Adempimento di Obblighi Legali** (base giuridica: obbligo legale — Art. 6(1)(c) GDPR)
- Adempimento di obblighi previsti da legge, regolamenti e normative applicabili;
- Risposta a richieste legittime delle autorità competenti.

**C. Interesse Legittimo** (base giuridica: interesse legittimo — Art. 6(1)(f) GDPR)
- Miglioramento dell'Applicazione e dell'esperienza d'uso;
- Prevenzione di frodi e abusi;
- Sicurezza del sistema.

**D. Consenso** (base giuridica: consenso — Art. 6(1)(a) GDPR)
- Attivazione di specifiche autorizzazioni di sistema (rete locale, notifiche, ecc.);
- Trasferimento internazionale dei dati verso paesi al di fuori del SEE (USA), se applicabile.

### 2.2 Trasferimento Internazionale dei Dati

Solo se Crashlytics è attivo, i dati di crash potrebbero essere trasferiti in paesi al di fuori dello Spazio Economico Europeo (SEE), in particolare negli **Stati Uniti d'America** (server Firebase).

Il trasferimento si basa sulle **Clausole Contrattuali Standard (SCC)** adottate dalla Commissione Europea, incorporate nel Data Processing Agreement (DPA) di Google Firebase, accettato dal Titolare. Una copia delle SCC è disponibile su richiesta.

Per i residenti in California (USA), si applicano anche le tutele del California Consumer Privacy Act (CCPA).

## 3. SERVIZI DI TERZI E CONDIVISIONE DEI DATI

### 3.1 Responsabili del Trattamento

Il Titolare si avvale del seguente responsabile del trattamento:

| Servizio | Fornitore | Dati Trattati | Localizzazione |
|---|---|---|---|
| **Firebase Crashlytics** *(opzionale)* | Google LLC | Report di crash, identificativo anonimo di installazione, dati sul dispositivo | USA |

### 3.2 Titolari Autonomi del Trattamento

Alcuni servizi integrati nell'Applicazione agiscono come titolari autonomi del trattamento:
- **Apple Inc.** — per il sistema operativo iOS/macOS e le autorizzazioni di sistema.

Per questi servizi, gli Utenti sono invitati a consultare le rispettive informative privacy:
- Apple: https://www.apple.com/legal/privacy/
- Google: https://policies.google.com/privacy

### 3.3 Nessuna Vendita di Dati Personali

Il Titolare **NON vende**, **NON cede** e **NON commercializza** i dati personali degli Utenti a terzi. L'Applicazione non è un servizio basato sulla monetizzazione dei dati degli utenti. Ciò include la conformità al "right to opt-out of sale of personal information" del CCPA per gli utenti californiani.

## 4. PERIODO DI CONSERVAZIONE DEI DATI

I dati personali sono conservati per il tempo strettamente necessario al conseguimento delle finalità per cui sono stati raccolti e, comunque, non oltre:

| Categoria di Dati | Periodo di Conservazione |
|---|---|
| Dati delle scansioni e cronologia | Fino alla cancellazione da parte dell'Utente o alla disinstallazione dell'App |
| Report di crash (Crashlytics) | Fino a 90 giorni |

Alla scadenza del periodo di conservazione, i dati saranno cancellati o resi irreversibilmente anonimi, salvo che la legge non richieda diversamente.

## 5. DIRITTI DELL'UTENTE (GDPR)

Ai sensi degli articoli 15-22 del GDPR, l'Utente ha i seguenti diritti:

### 5.1 Diritto di Accesso (Art. 15)
L'Utente ha il diritto di ottenere la conferma che sia o meno in corso un trattamento di dati personali che lo riguardano e, in tal caso, di ottenere l'accesso ai dati personali.

### 5.2 Diritto di Rettifica (Art. 16)
L'Utente ha il diritto di ottenere la rettifica dei dati personali inaccurati che lo riguardano senza ingiustificato ritardo.

### 5.3 Diritto alla Cancellazione ("Diritto all'Oblio") (Art. 17)
L'Utente ha il diritto di ottenere la cancellazione dei dati personali che lo riguardano senza ingiustificato ritardo, nei casi previsti dal GDPR.

### 5.4 Diritto alla Limitazione del Trattamento (Art. 18)
L'Utente ha il diritto di ottenere la limitazione del trattamento nei casi previsti dal GDPR.

### 5.5 Diritto alla Portabilità dei Dati (Art. 20)
L'Utente ha il diritto di ricevere i dati personali che lo riguardano, forniti al Titolare, in un formato strutturato, di uso comune e leggibile da dispositivo automatico, e il diritto di trasmetterli a un altro titolare senza impedimenti.

### 5.6 Diritto di Opposizione (Art. 21)
L'Utente ha il diritto di opporsi in qualsiasi momento, per motivi connessi alla sua situazione particolare, al trattamento dei dati personali che lo riguardano basato su interesse legittimo.

### 5.7 Diritto di Revoca del Consenso (Art. 7)
L'Utente ha il diritto di revocare il proprio consenso in qualsiasi momento, senza pregiudicare la liceità del trattamento basata sul consenso prima della revoca.

### 5.8 Diritto di Reclamo (Art. 77)
L'Utente ha il diritto di proporre reclamo al Garante per la Protezione dei Dati Personali (https://www.garanteprivacy.it) o all'autorità di controllo dello Stato membro dell'UE in cui risiede abitualmente, lavora o dove si è verificata la presunta violazione.

### 5.9 Come Esercitare i Diritti

Per esercitare i propri diritti, l'Utente può contattare il Titolare in qualsiasi momento all'indirizzo: **support@aldeveloping.it**. Il Titolare risponderà alla richiesta entro 30 giorni, prorogabili di ulteriori 60 giorni per richieste particolarmente complesse, informando l'Utente di tale proroga entro 30 giorni dalla ricezione della richiesta.

## 6. DIRITTI DEI RESIDENTI IN CALIFORNIA (CCPA)

Per i residenti in California, USA, il California Consumer Privacy Act (CCPA) garantisce i seguenti ulteriori diritti:

### 6.1 Diritto di Conoscere
Il diritto di richiedere la divulgazione delle categorie e dei dati personali specifici raccolti, delle fonti, della finalità e dei terzi con cui i dati vengono condivisi.

### 6.2 Diritto di Cancellazione
Il diritto di richiedere la cancellazione dei dati personali raccolti, fatte salve alcune eccezioni.

### 6.3 Diritto di Non Discriminazione
Il diritto di non ricevere trattamenti discriminatori per aver esercitato i diritti previsti dal CCPA.

### 6.4 Nessuna Vendita di Dati
Il Titolare NON vende i dati personali di alcun Utente, inclusi gli utenti californiani. Pertanto non è richiesto un link "Do Not Sell My Personal Information".

Per esercitare i diritti CCPA, contattare **support@aldeveloping.it**.

## 7. MISURE DI SICUREZZA

Il Titolare adotta adeguate misure di sicurezza tecniche e organizzative per proteggere i dati personali da accessi non autorizzati, distruzione, perdita, alterazione o divulgazione. Queste includono:

- **Trattamento locale dei dati**: le scansioni e i dati di rete vengono elaborati e conservati esclusivamente sul dispositivo dell'Utente (protezione dati iOS/macOS);
- **Crittografia in transito**: le eventuali comunicazioni verso i server (es. report di crash) avvengono su TLS/HTTPS;
- **Minimizzazione dei dati**: il Titolare raccoglie solo i dati strettamente necessari alle finalità dichiarate.

## 8. DATI DEI MINORI

L'Applicazione non è specificamente rivolta a minori di 13 anni (o 16 anni per i residenti di alcuni Stati membri dell'UE). Il Titolare non raccoglie consapevolmente dati personali di minori senza il consenso dei genitori o tutori. Se un Utente è genitore o tutore e ritiene che un minore abbia fornito dati personali al Titolare, si prega di contattare **support@aldeveloping.it** per richiederne la cancellazione.

L'Applicazione non implementa un meccanismo di verifica dell'età.

## 9. AGGIORNAMENTI DELL'INFORMATIVA

La presente Informativa può essere soggetta ad aggiornamenti periodici. Il Titolare informerà gli Utenti delle modifiche sostanziali tramite l'Applicazione o altri canali appropriati. La data dell'ultimo aggiornamento è indicata in cima al documento.

## 10. CONTATTI

Per qualsiasi domanda, richiesta o esercizio dei diritti relativi alla presente Informativa sulla Privacy, l'Utente può contattare:

**Titolare del Trattamento:**
Alain S. M. Lima
Email: support@aldeveloping.it
Sede legale: Palermo, Italia

Per la gestione delle autorizzazioni di sistema e dei dati su iOS/macOS: Apple (https://www.apple.com/legal/privacy/)

---

**© 2026 Alain S. M. Lima. Tutti i diritti riservati.**
