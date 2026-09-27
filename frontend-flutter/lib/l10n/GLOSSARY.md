# Game-term glossary

One term per game concept and language: every `app_<lang>.arb` uses it, on every screen
(table, action messages, round end, rules sheet, tutorial, statistics). French
(`app_fr.arb`) is the template; the game is `GAME_RULES.md`. A new string, or a new
language, takes its terms from here; a term changed here changes in its whole ARB file.
Reviewed 2026-09-27 (`chore/flutter-l10n-review`): a stronger-model review, not yet a fluent
speaker's — the pull request lists the terms held least certain.

| Concept | en | fr | es | pt (BR) | de | ru | ja | hi | id | ar |
|---|---|---|---|---|---|---|---|---|---|---|
| Deck: the face-down draw pile (`gameDeckLabel`) | deck | pioche | mazo | monte | Ziehstapel | колода | 山札 | डेक | dek | كومة السحب |
| Discard pile: the cards played, the ones a player may take among them | discard pile | défausse | pila de descarte | descarte | Ablagestapel | сброс | 捨て札 | फेंके गए कार्ड | tumpukan buangan | كومة الرمي |
| The cards the previous player just played, to take (`gameTableNextLabel`) | Up for grabs next | À prendre ensuite | Para tomar | Para pegar | Zum Nehmen | Можно взять | 取れるカード | ले सकते हैं | Bisa diambil | متاحة للأخذ |
| The cards laid down this turn (`gameTablePlayedLabel`) | Played | Posées | Jugadas | Jogadas | Gelegt | Выложено | 出したカード | खेले गए | Dimainkan | الملعوبة |
| Draw: the turn's second step, a card from the deck (or the pile) | draw | piocher | robar | comprar | ziehen | взять | 引く | उठाएँ | ambil | اسحب (سحب) |
| Take: one card from the pile | take | prendre | tomar | pegar | nehmen | взять | 取る | लें | ambil | خذ (أخذ) |
| Play: lay cards down | play | jouer | jugar | jogar | spielen | сыграть | 出す | खेलें | mainkan | العب |
| Call ZapZap | call ZapZap | appeler ZapZap | cantar ZapZap | anunciar ZapZap | ZapZap rufen | объявить ZapZap | ZapZap を宣言 | ZapZap बोलें | serukan ZapZap | أعلِن ZapZap |
| Counteracted (a ZapZap) | counteracted | contré | contrarrestado | rebatido | gekontert | перебит | 阻止 | निरस्त | ditangkis | مُحبَط |
| Round | round | manche | ronda | rodada | Runde | раунд | ラウンド | राउंड | putaran | جولة |
| Hand, hand value | hand, hand value | main, valeur de la main | mano, valor de la mano | mão, valor da mão | Hand, Handwert | рука, очки руки | 手札, 手札の点数 | हाथ, हाथ के अंक | kartu di tangan, nilai tangan | اليد، قيمة اليد |
| Lowest hand | lowest hand | main la plus basse | mano más baja | mão mais baixa | niedrigste Hand | наименьшая рука | 最も低い手札 | सबसे कम हाथ | tangan terendah | أقل يد |
| Eliminated (above 100 points) | eliminated, out | éliminé | eliminado | eliminado | ausgeschieden | выбыл | 脱落 | बाहर | tersingkir | مُقصى |
| Golden Score | Golden Score | Golden Score | Golden Score | Golden Score | Golden Score | Golden Score | Golden Score | Golden Score | Golden Score | Golden Score |
| Run (3+ consecutive, one suit) | run | suite | escalera | sequência | Reihe | последовательность | 階段 | सीक्वेंस | urutan | سلسلة |
| Pair | pair | paire | par | par | Paar | пара | ペア | जोड़ी | pasangan | زوج |
| Joker | joker | joker | comodín | coringa | Joker | джокер | ジョーカー | जोकर | joker | جوكر |
| Penalty | penalty | pénalité | penalización | penalidade | Strafe | штраф | ペナルティ | पेनल्टी | penalti | عقوبة |
| Turn | turn | tour | turno | vez | Zug | ход | 番 | बारी | giliran | دور |
| Game (a party) | game | partie | partida | partida | Partie | партия | ゲーム | गेम | permainan | لعبة |
| Suits ♠ ♥ ♣ ♦ (`suit*`) | Spades, Hearts, Clubs, Diamonds | pique, cœur, trèfle, carreau | espadas, corazones, tréboles, diamantes | espadas, copas, paus, ouros | Pik, Herz, Kreuz, Karo | пики, червы, трефы, бубны | スペード, ハート, クラブ, ダイヤ | हुकुम, पान, चिड़ी, ईंट | sekop, hati, keriting, wajik | البستوني، القلوب، السباتي، الديناري |
| Card | card | carte | carta | carta | Karte | карта | カード (枚) | कार्ड | kartu | بطاقة |
| Addressing the player | you | tu | tú | você | du | ты | polite form (です/ます) | आप | kamu | masculine singular |

- `ZapZap` and `Golden Score` stay in Latin script in every language, as the brand and the
  mode's name.
- The draw step (`gameStepDraw`, `gameDrawButton`) covers both sources, as French
  "Piocher" does: a card from the deck, or one taken from the pile. Where the draw verb and
  the take verb are one word (ru, id), the label that names the card (`gameMoveTake`) tells
  them apart.
- Quoted labels (`tutorialTakePile*` quote `gameTableNextLabel`) repeat the label exactly.
