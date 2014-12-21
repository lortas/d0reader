d0reader
========
Der d0reader ließt über tty einen Lesekopf (typischerweise Infrarot) aus und schreibt die erhaltenen Daten in einem vorgegebenen Intervall in eine Textdatei (Logdatei) in das Dateisystem. Es erwartet die erhaltenen Daten im d0-Format.

d0-Schnittstelle
----------------
Optische Datenschnittstelle D0 ist nach Anforderungen DIN EN 62056-21 aufgebaut und eHZ kompatibel (VDN- Lastenheft „Elektronische Haushaltzähler“ Version 1.02). Protokoll entspricht DIN EN 625056-21 und DIN EN 625056-61 mode D, 9600 Baud (Z=5). Die repetierende Ausgabe der Telegramme ist in einem Zeitraster von 2s festgelegt worden. [Quelle: http://propertools.org/index.php/de/hardware/kommunikation/item/spezifikation-d0-schnittstelle-q3dx]
