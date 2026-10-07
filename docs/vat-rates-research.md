# VAT / GST rate research for the VAT panel presets

Researched 2026-10-06. Rates are those in force on that date. Use this as input for the quick-pick presets, not as tax advice.

**How to read this**

- **Std** is the standard rate. **Additional** lists up to three other rates that shoppers commonly meet — usually reduced rates, but sometimes higher (Argentina 27, India 40, Canada's HST); obscure or sector-only rates are left out. The JSON field is `additional`.
- **Latest change** is the effective date of the most recent change to a rate in this row. "—" means no 2024–2026 change was found.
- **Conf.**
  - **H**: an official source, checked this session, confirms the rate is current.
  - **M**: a reputable secondary source (PwC, KPMG, EY, BDO, Deloitte, Big-4/law-firm alerts, VAT-news trackers), or an official table that is a little out of date but corroborated.
  - **L**: sources conflict, the rate is unclear, or it was not checked individually this session.
- **EU source.** The EC's *VAT rates applied in the Member States* PDF could not be retrieved; the EC VAT-rates page now points to the TEDB database instead. The EU rows therefore use the EU's official **Your Europe** VAT-rates table (last updated 13 July 2026): <https://europa.eu/youreurope/business/taxation/vat/vat-rules-rates/index_en.htm>. Changes after that date were checked separately.

## European Union (27)

| Country | ISO | Std | Additional (common) | Latest change | Source | Conf. |
|---|---|---|---|---|---|---|
| Austria | AT | 20 | 10, 13, **4.9** (staple foods) | 2026-07-01 (staple foods 10 → 4.9) | Your Europe; Austrian Parliament approval reported by meridianglobalservices.com/austria-4-9-vat-rate-approved, bta.bg | M (Your Europe table predates the 4.9 rate) |
| Belgium | BE | 21 | 12, 6 | 2026-03-01 (hotels/campsites 6 → 12) | Your Europe; bdo.be 2026 alert | H |
| Bulgaria | BG | 20 | 9 | — | Your Europe | H |
| Croatia | HR | 25 | 13, 5 | — | Your Europe | H |
| Cyprus | CY | 19 | 9, 5, 3 | — | Your Europe | H |
| Czechia | CZ | 21 | 12 | 2024-01-01 (10 and 15 merged into 12) | Your Europe | H |
| Denmark | DK | 25 | — (0 on newspapers only) | — | Your Europe | H |
| Estonia | EE | 24 | 13 (accommodation), 9 (books, press, medicines) | 2025-07-01 (22 → 24); accommodation 13 since 2025-01-01 | Your Europe (lists only 9); trykintsugi/avalara for 13 | H (std) / M (13) |
| Finland | FI | 25.5 | 13.5 (food, restaurants, transport…), 10 (books, press, medicines) | 2026-01-01 (14 → 13.5); std 24 → 25.5 on 2024-09-01 | Your Europe | H |
| France | FR | 20 | 10, 5.5, 2.1 | — | Your Europe | H |
| Germany | DE | 19 | 7 | 2026-01-01 (restaurant food back to 7, permanent; drinks stay 19) | Your Europe; Bundesrat approval 2025-12-19 (DLA Piper alert) | H |
| Greece | GR (EL in EU usage) | 24 | 13, 6 | — (islands get 30% lower rates, e.g. 17 / 9 / 4) | Your Europe | H |
| Hungary | HU | 27 | 18, 5 | — | Your Europe | H |
| Ireland | IE | 23 | 13.5, 9 (restaurants, hot takeaway, hairdressing) | 2026-07-01 (restaurants 13.5 → 9) | Your Europe; Revenue TDM via rsm.global, ibec.ie | H |
| Italy | IT | 22 | 10, 5, 4 | — | Your Europe | H |
| Latvia | LV | 21 | 12, 5 | 2026-07-01 (temporary 12 on bread, milk, poultry, eggs to 2027-06-30); 2026-01-01 (fruit/veg 12) | Your Europe; meridianglobalservices.com Latvia 2026 budget | H |
| Lithuania | LT | 21 | 12, 5 | 2026-01-01 (9 → 12; books 9 → 5; heating 9 → 21) | Your Europe; fiscal-requirements.com #4772 | H |
| Luxembourg | LU | 17 | 14, 8, 3 | — (2023 temporary cut ended) | Your Europe | H |
| Malta | MT | 18 | 7, 5 (12 is a parking-type rate) | — | Your Europe | H |
| Netherlands | NL | 21 | 9 | 2026-01-01 (accommodation 9 → 21; campsites stay 9) | Your Europe; fiscalead.com | H |
| Poland | PL | 23 | 8, 5 | — | Your Europe | H |
| Portugal | PT | 23 | 13, 6 | — (mainland rates; Azores and Madeira lower) | Your Europe | H |
| Romania | RO | 21 | 11 | 2025-08-01 (19 → 21; 9 and 5 merged into 11) | Your Europe; EY alert 2025-1622 | H |
| Slovakia | SK | 23 | 19, 5 | 2025-01-01 (20 → 23; 10 → 19 / 5); 2026-01-01 sugary/salty foods 19 → 23 | Your Europe; PwC SK | H |
| Slovenia | SI | 22 | 9.5, 5 | — | Your Europe | H |
| Spain | ES | 21 | 10, 4 | — (Canary Islands use IGIC 7, not VAT) | Your Europe | H |
| Sweden | SE | 25 | 12, 6 | 2026-04-01 (food 12 → 6, temporary to 2027-12-31; eating in stays 12) | Your Europe; Skatteverket via forvismazars.com/se | H |

## Rest of Europe

| Country | ISO | Std | Additional (common) | Latest change | Source | Conf. |
|---|---|---|---|---|---|---|
| United Kingdom | GB | 20 | 5, 0 | 2026-10-01: temporary 0 on domestic electricity in Great Britain to 2027-03-31 (Northern Ireland stays 5) | gov.uk/guidance/rates-of-vat-on-different-goods-and-services (updated 2026-07-10); HMRC R&C Brief 10 (2026) | H |
| Switzerland | CH | 8.1 | 3.8 (accommodation), 2.6 | 2024-01-01 (7.7 → 8.1) | estv.admin.ch/en/vat-rates-switzerland | H |
| Liechtenstein | LI | 8.1 | 3.8, 2.6 | 2024-01-01 (same VAT area as Switzerland) | PwC CH; ESTV | M |
| Norway | NO | 25 | 15 (food), 12 (transport, cinema, hotels) | — | Skatteetaten rates via trykintsugi/taxenlight | M |
| Iceland | IS | 24 | 11 | 2026-09-01: fuel back to 24 after a temporary 11 (May–Aug 2026) | KPMG TNF 2026-06 | M |
| Russia | RU | **22** | 10, 0 | 2026-01-01 (20 → 22; Federal Law 425-FZ of 2025-11-28) | Thomson Reuters 2026-02; Meduza; Bloomberg Tax | M |
| Ukraine | UA | 20 | 7 (medicines, hotels, culture); 14 is agricultural only | — | PwC WWTS Ukraine | M |
| Turkey | TR | 20 | 10, 1 | 2023-07-10 (18 → 20) | PwC / trykintsugi | M |
| Montenegro (EUR) | ME | 21 | 7 | — | vatupdate.com global table (Jul 2026) | M |
| Andorra (EUR) | AD | 4.5 | 2.5, 1 | — | vatupdate.com global table (Jul 2026) | M |
| Monaco (EUR) | MC | 20 | 10, 5.5, 2.1 | — (uses the French VAT system) | French rates; Your Europe | M |

## Americas

| Country | ISO | Std | Additional (common) | Latest change | Source | Conf. |
|---|---|---|---|---|---|---|
| Canada | CA | 5 (federal GST) | HST combined: ON 13, NS 14, NB/NL/PE 15. QC: GST 5 + QST 9.975 = 14.975 | 2025-04-01 (NS HST 15 → 14) | canada.ca CRA GST/HST rate table | H |
| United States | US | — | No national VAT. State and local sales taxes run from 0 to about 10+%, and the price is shown before tax | — | — | H (structural) |
| Mexico | MX | 16 | 8 (northern/southern border-zone incentive, registered businesses only; to 2026-12-31), 0 (food, medicines) | Border decree renewed 2025-12-31 for 2026 | DOF decree via satfacil.com.mx, adn40.mx | M |
| Brazil | BR | — (no single rate) | Legacy ICMS (state, about 17–23%), ISS (municipal, 2–5%), PIS/COFINS, IPI. 2026 test year: CBS 0.9 + IBS 0.1 shown on invoices | 2026-01-01 (CBS/IBS test rates); CBS replaces PIS/COFINS from 2027; full IBS/CBS by 2033 (reference rate about 28%) | EC 132/2023, LC 214/2025, via lookuptax/trykintsugi | L (no meaningful single preset) |
| Argentina | AR | 21 | 10.5, 27 (utilities, business telecoms) | — (rate unification under discussion, Jul 2026) | iprofesional.com 2026-07; PwC | M |
| Chile | CL | 19 | — | — | PwC | M |
| Colombia | CO | 19 | 5 | 2026: spirits briefly 5 → 19 (1–29 Jan), back to 5 after the decree fell | siemprealdia.co, publimetro.co | M |
| Peru | PE | 18 (IGV 16 + IPM 2) | 10.5 (micro/small restaurants and hotels: IGV 8 + IPM 2.5) | Reduced regime runs to 2026-12-31, then a step-up in 2027 | Congress extension (larepublica.pe 2024-12) | M |
| Paraguay (₲) | PY | 10 | 5 (basic food, medicines) | — | lanacion.com.py 2026-07 | M |
| Costa Rica (₡) | CR | 13 | 4, 2, 1 (basic food basket) | — (government floating a higher basket rate, Jul 2026) | siemprealdia.co; delfino.cr 2026-07 | M |
| Ecuador ($) | EC | 15 | 5 (some building materials) | 2024-04-01 (12 → 15) | expreso.ec / eldiario.ec 2025-12 (SRI) | M |
| El Salvador ($) | SV | 13 | — | — | trykintsugi LatAm | M |
| Panama ($) | PA | 7 | — (10 / 15 are *higher* rates on alcohol/hotels and tobacco) | — | vatupdate.com Jul 2026 | M |
| Uruguay ($) | UY | 22 | 10 | — | vatupdate.com Jul 2026 | M |
| Dominican Republic ($) | DO | 18 | 16 | — | vatupdate.com Jul 2026 | M |
| Puerto Rico ($) | PR | 11.5 (IVU sales tax, not VAT) | — | — | not checked this session | L |
| Jamaica ($) | JM | 15 (GCT) | — | — | not checked this session | L |
| Trinidad & Tobago ($) | TT | 12.5 | — | — | not checked this session | L |
| Bahamas ($) | BS | 10 | — | — | not checked this session | L |

## Asia-Pacific

| Country | ISO | Std | Additional (common) | Latest change | Source | Conf. |
|---|---|---|---|---|---|---|
| Australia | AU | 10 (GST) | 0 (GST-free basic food, health) | — | ATO (page returned 403; rate well established) / PwC | M |
| New Zealand | NZ | 15 (GST) | — | — | ird.govt.nz/gst | H |
| Japan | JP | 10 | 8 (food and non-alcoholic drinks excluding dining in; subscribed newspapers) | 2019-10-01. **Planned:** food 8 → 1 for two years from April 2027 | nta.go.jp/english/taxes/consumption_tax/01.htm; plan via vatupdate 2026-05, japantoday | H (current) |
| South Korea | KR | 10 | — (basic food exempt) | — | PwC / trykintsugi | M |
| China | CN | 13 | 9, 6 (3 = small-scale taxpayer levy) | 2026-01-01 VAT Law in force, rates unchanged | Rödl & Partner 2026-01 | M |
| Taiwan ($) | TW | 5 (business tax) | — | — | PwC WWTS Taiwan | M |
| Hong Kong ($) | HK | 0 (no VAT/GST) | — | — | — | H (structural) |
| Singapore ($) | SG | 9 (GST) | — | 2024-01-01 (8 → 9) | IRAS (page content not extractable); PwC | M |
| India | IN | 18 (GST) | 5, 40 (sin/luxury goods), 0 (3 on gold) | 2025-09-22 (GST 2.0: 12 and 28 slabs removed → 5 / 18 / 40) | CBIC notifications 2025-09-17 (EY India alert) | M |
| Thailand | TH | 7 (statutory 10) | — | Royal Decree No. 807 (2026) keeps 7 from 2026-10-01 to 2027-09-30 | moneyandbanking.co.th; Orbitax | M |
| Vietnam | VN | 10 | 8 (temporary cut, to 2026-12-31), 5 | 2025-07-01 (8 extended; Res. 204/2025/QH15) | DFDL; Bloomberg Tax | M |
| Philippines | PH | 12 | — | — (bills to cut to 10 still pending in the Senate) | Bloomberg Tax 2026-02; vatupdate 2026-01 | M |
| Indonesia | ID | 12 statutory; **11 effective** for non-luxury goods (DPP 11/12) | 12 effective on luxury (PPnBM) goods only | 2025-01-01 (PMK 131/2024) | Baker McKenzie; KPMG ID | M |
| Malaysia | MY | SST (not a VAT): sales tax 10 / 5; service tax 8 / 6 | — | 2025-07-01 SST scope expanded; 2026-01-01 rental/leasing services 8 → 6 | 3ecpa.com.my; trykintsugi | M |
| Laos (₭) | LA | 10 | — | 2024 (reinstated 10 from 7; Ordinance 003/PDT) | Tilleke & Gibbins; PwC | M |
| Mongolia (₮) | MN | 10 | — | — (tax package for 2027-01-01 does not change the rate) | PwC Mongolia alert 01/2026; KPMG 2026-03 | M |
| Fiji ($) | FJ | **12.5** | 0 (22 essential items) | 2025-08-01 (15 → 12.5) | Fiji Budget 2025-26 (islandsbusiness.com); Sovos | M |

## Middle East & Africa

| Country | ISO | Std | Additional (common) | Latest change | Source | Conf. |
|---|---|---|---|---|---|---|
| United Arab Emirates | AE | 5 | — | 2018-01-01 | tax.gov.ae (FTA) | H |
| Saudi Arabia | SA | 15 | — | 2020-07-01 (5 → 15) | ZATCA via trykintsugi / PwC | M |
| Israel (₪) | IL | 18 | 0 (fresh fruit and vegetables; Eilat) | 2025-01-01 (17 → 18) | JNS; PwC | M |
| South Africa | ZA | 15 | 0 (basic foods) | 2018-04-01. The planned 15.5 / 16 rises were reversed | sars.gov.za VAT page | H |
| Nigeria (₦) | NG | 7.5 | 0 (basic food, from 2026) | 2026-01-01 (Nigeria Tax Act 2025: rate unchanged, zero-rating widened) | BDO; Forvis Mazars NG | M |
| Egypt | EG | 14 | 5 (some medical devices) | 2025/2026 amendments (construction moved to 14) | Deloitte ME; Andersen EG | M |
| Kenya | KE | 16 | 8 (petroleum products) | 2026-07-01 Finance Act 2026 (scope changes only) | Mondaq; PwC | M |
| Ghana (₵) | GH | **20** effective (VAT 15 + NHIL 2.5 + GETFund 2.5, no longer cascading) | — | 2026-01-01 (VAT Act 2025, Act 1151: COVID levy scrapped, effective rate about 21.9 → 20) | Crowe GH; graphic.com.gh | M |
| Liberia ($) | LR | 13 (GST) | — | 2026-05-01 (GST 12 → 13). **VAT 18 from 2027-01-01** | vatcalc.com / innovatetax.com | M |
| Zimbabwe ($) | ZW | 15.5 | — | — | vatupdate.com Jul 2026 | M |

## Count by confidence

84 countries in total.

- **H: 35**. That is 26 EU states (all except AT) plus GB, CH, CA, US, NZ, JP, HK, AE, ZA. US and HK are rated on the structural point: no national VAT. Estonia's 13% rate is only M.
- **M: 44**. AT, LI, NO, IS, RU, UA, TR, ME, AD, MC, MX, AR, CL, CO, PE, PY, CR, EC, SV, PA, UY, DO, AU, KR, CN, TW, SG, IN, TH, VN, PH, ID, MY, LA, MN, FJ, SA, IL, NG, EG, KE, GH, LR, ZW.
- **L: 5**. BR (no single rate), PR, JM, TT, BS (not checked individually).

## Changes & caveats

**Changes already in force (2024 to Oct 2026)**

1. **Russia 20 → 22** on 2026-01-01. Some aggregator tables still say 20, including vatupdate's July 2026 table.
2. **Thailand stays 7** until 2027-09-30 under Royal Decree 807/2026. vatupdate's table wrongly said it rises to 10 on 2026-10-01.
3. **Fiji 15 → 12.5** on 2025-08-01. vatupdate's table still says 15.
4. **India GST 2.0** on 2025-09-22: slabs are now 5 / 18 / 40, and the 12 and 28 slabs are gone. Many tables still show 5 / 12 / 18 / 28.
5. **Austria** cut staple foods 10 → 4.9 on 2026-07-01; restaurants are excluded. This is not yet in the Your Europe table, and no end date was found.
6. **Estonia 22 → 24** on 2025-07-01, made permanent. Accommodation moved to 13 from 2025.
7. **Finland**: standard 25.5 since 2024-09-01; reduced 14 → 13.5 on 2026-01-01.
8. **Slovakia**: 23 / 19 / 5 since 2025-01-01. Sugary and salty foods moved 19 → 23 in 2026.
9. **Romania**: 19 → 21 and a single reduced 11 since 2025-08-01. HoReCa stays at 11; aligning it to 21 was discussed but not adopted.
10. **Czechia**: 10 and 15 merged into 12 on 2024-01-01.
11. **Lithuania** on 2026-01-01: 9 → 12, books → 5, heating → 21.
12. **Latvia**: fruit and vegetables at 12 from 2026-01-01. Temporary 12 on bread, milk, poultry and eggs from 2026-07-01 to 2027-06-30.
13. **Germany**: restaurant food at 7, permanent, from 2026-01-01.
14. **Netherlands**: accommodation 9 → 21 on 2026-01-01.
15. **Belgium**: hotels and campsites 6 → 12 on 2026-03-01. The parallel rises for takeaway food and events were postponed after the Council of State objected; their new date is unclear.
16. **Sweden**: food 12 → 6 from 2026-04-01, temporary to 2027-12-31.
17. **Ireland**: restaurants, hot takeaway and hairdressing 13.5 → 9 from 2026-07-01.
18. **Switzerland and Liechtenstein**: 8.1 / 3.8 / 2.6 since 2024-01-01.
19. **Israel**: 17 → 18 on 2025-01-01.
20. **Indonesia**: statutory 12 since 2025-01-01, but the effective rate stays 11 on everything except luxury goods.
21. **Canada**: Nova Scotia HST 15 → 14 on 2025-04-01.
22. **Ghana**: VAT Act 2025 in force since 2026-01-01; the effective rate drops to 20.
23. **Liberia**: GST 12 → 13 on 2026-05-01.
24. **China**: VAT Law in force 2026-01-01; rates unchanged.
25. **Nigeria**: the 2026 reform kept 7.5 (rises to 10–15 had been proposed and were dropped).
26. **South Africa**: the 15.5 / 16 rises were reversed and the rate stays 15.
27. **UK**: temporary 0 on domestic electricity in Great Britain from 2026-10-01. A temporary reduced rate on children's meals and family attractions applied June–September 2026 and has ended.
28. **Iceland**: temporary 11 on fuel, May–August 2026, now ended.

**Scheduled or possible within about 6 months (to April 2027)**

- **Vietnam**: the temporary 8 rate ends 2026-12-31 unless extended. It has been extended every year since 2022.
- **Mexico**: the 8 border-zone incentive runs to 2026-12-31 and is normally renewed by decree.
- **Peru**: the reduced restaurant/hotel regime steps up from 2027-01-01. Reports say the IGV portion goes to 12 in 2027 and back to standard in 2028.
- **Liberia**: VAT at 18 replaces the 13 GST on 2027-01-01.
- **Brazil**: CBS replaces PIS/COFINS from 2027-01-01.
- **Switzerland and Liechtenstein**: a referendum on 2026-11-29 on 8.1 → 8.5 (and 3.8 → 4.0). If approved, it takes effect 2028-01-01 at the earliest. Not within 6 months, but worth watching.
- **Japan**: the government has finalised a plan to cut food 8 → 1 for two years from April 2027. Whether the legislation has passed was not confirmed.
- **UK**: the GB domestic-electricity 0 rate ends 2027-03-31.
- **Denmark**: 0 on books is proposed for 2027. The earlier bill lapsed at the 2026 election.
- **Proposals only, not law**: Philippines 12 → 10 (bills in the Senate); Argentina rate unification (possibly 18–19); Costa Rica higher basic-basket rate; Ukraine 20 → 15 (IMF track, by about 2028, no date).

**Structural caveats for the presets**

- **Canada**: show GST 5 plus HST 13 / 14 / 15 as separate presets. Quebec is GST 5 + QST 9.975 = 14.975 combined; the two have been non-compounding since 2013. BC, MB and SK add a separate PST (7 / 7 / 6).
- **US**: no VAT; there is no meaningful national preset.
- **Malaysia**: the SST is a single-stage sales and service tax, not a VAT.
- **Brazil**: no single consumer rate exists until the reform finishes.
- **Ghana**: the 20 combines VAT with two levies.
- **Peru**: the 18 combines IGV 16 with the 2 municipal tax (IPM).
- **Indonesia**: the 12 headline rate overstates the 11 effective rate.
- **Thailand**: the statutory 10 is suspended in favour of 7.
- **Hong Kong**: no VAT.
- **Regional rates not reflected**: Canary Islands IGIC 7, Azores and Madeira, the Greek islands, Northern Ireland electricity, and Mexico's border zone.
- **Official sources that could not be read** (blocked or content not extractable): the EC PDF, ATO and IRAS pages, and vatcalc.com. For those rows the rate was confirmed through the secondary sources listed.
