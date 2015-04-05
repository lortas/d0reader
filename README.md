d0reader
========
Der d0reader ließt über tty einen Lesekopf (typischerweise Infrarot) aus und schreibt die erhaltenen Daten in einem vorgegebenen Intervall in eine Textdatei (Logdatei) in das Dateisystem. Es erwartet die erhaltenen Daten im d0-Format. 

d0-Schnittstelle
----------------
Optische Datenschnittstelle D0 ist nach Anforderungen DIN EN 62056-21 aufgebaut und eHZ kompatibel (VDN- Lastenheft „Elektronische Haushaltzähler“ Version 1.02). Protokoll entspricht DIN EN 625056-21 und DIN EN 625056-61 mode D, 9600 Baud (Z=5). Die repetierende Ausgabe der Telegramme ist in einem Zeitraster von 2s festgelegt worden. [Quelle: http://propertools.org/index.php/de/hardware/kommunikation/item/spezifikation-d0-schnittstelle-q3dx]

Verzeichnisse+Dateien
---------------------
/usr/local/bin/visuald0data.rb
/usr/local/bin/d0reader.rb
/usr/local/bin/send_meterreading.rb
/etc/cronscripts/visuald0data
/etc/cronscripts/send_meterreading
/etc/udev/rules.d/99-lesekopf.rules
/etc/d0reader.xml
/var/www/htdocs/index.html
/var/www/htdocs/cgi-bin/refresh_meterreading

/etc/cron.daily/visuald0data
/etc/cron.monthly/maile_zaehlerstand
