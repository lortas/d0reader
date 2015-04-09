#!/usr/bin/env ruby

require 'rexml/document'

configfile="/etc/d0reader.xml"
logpath=""
logfiles=""
@outputfolder_image=""
@outputfolder_text=""
@outputfolder_html=""
pidfile = "/var/run/visuald0data.pid"
@intervall = 1.0
initgnuplot = <<GNUPLOT
  set terminal png size 1500,700
  set timefmt "%y-%m-%d\t%H%M"
  set ylabel "Kilowatt (kW)"
  set xlabel 'Stunde (h)'
  set xrange [0:24]
  set style line 1 lt 1 lw 1
  set style fill solid 0.2
  set style data filledcurves y1=0
  set grid mxtics mytics
  set grid xtics ytics
  set xtics 3
  set mxtics 3
  set ytics 0.5
  set mytics 5
  set tics front
  set grid front
  set decimalsign ','
GNUPLOT

if File.exists? configfile
  config = REXML::Document.new File.new(configfile)
  if config == nil
    print("Parsing Error during reading configfile '%s'",configfile)
    exit
  end
  config=config.root
  config.elements.each("./LOGPATH") { |p| logpath = p.text }
  config.elements.each("./VISUAL/LOGFILES") { |f| logfiles = f.text }
  config.elements.each("./VISUAL/PIDFILE") { |f| pidfile = f.text }
  config.elements.each("./VISUAL/INTERVAL") { |f| @intervall = f.text.to_f }
  config.elements.each("./VISUAL/OUTPUTFOLDER[@type='image']") { |o| @outputfolder_image = o.text }
  config.elements.each("./VISUAL/OUTPUTFOLDER[@type='text']") { |o| @outputfolder_text = o.text }
  config.elements.each("./VISUAL/OUTPUTFOLDER[@type='html']") { |o| @outputfolder_html = o.text }
else
  printf("No configfile '%s' found.\n",configfile)
  exit
end

@intervall_h = @intervall/3600  # Umrechnung der Intervallgröße von Sekunde auf Stunde

# Gibt es bereits ein PID-File
if File.exists? pidfile
  # Lese die PID
  pid=File.open(pidfile,"r")
  lastpid=pid.gets
  # Teste ob der prozess wirklich läuft
  if `ps -p #{lastpid} -o comm=` != ""
    # ok, prozess läuft noch. Dann warten wir bis er fertig ist und beenden dann ohne selbst noch mal alles neu zu berechnen.
    printf("An other prozess is already running.\n",lastpid)
    while `ps -p #{lastpid} -o comm=` != ""
      printf("Warte.\n")
      sleep 10
    end
    printf("ending without calculation.\n")
    exit
  end
  pid.close
end
pid=File.open(pidfile,"w")
pid << Process.pid
pid.close

def split(intervall,line)
  line.chop!
  line.strip!
  (t,c)=line.split("\t")
  return t.to_f,c.to_f,(t.to_f/intervall).to_i
end

def writeplotdata(out,data,step)
  t=0
  data.each do |v|
    # Schreibe Kurvenpunkt am Intervallanfang
    out << sprintf("%f\t\%f\n",t,v)
    t+=step
    # Schreibe Kurvenpunkt am Intervallende
    out << sprintf("%f\t\%f\n",t,v)
  end
end

def read_durchschnittverbrauch(filename,intervall)
  intervallsize=(24.0*60.0*60.0)/intervall.to_f
  durchschnittverbrauch=Array.new(intervallsize,1.0)
  if File.exists? filename
    i=0
    File.open(filename,"r").each_line do |line|
      durchschnittverbrauch[i]=line.strip.to_f
      i+=1
    end
  end
  return durchschnittverbrauch
end

def write_durchschnittverbrauch(filename,durchschnittverbrauch)
  fh=File.open(filename,"w")
  durchschnittverbrauch.each do |v|
    fh << sprintf("%f\n",v)
  end
end

def calculate_csv_file(csvfilename)
  printf("Processing '%s'.\n",csvfilename)
  allvalues=[]

  maxvalue=[0,0]
  minvalue=[0,10]
  stats=File.open(csvfilename, "r")
  lastvalues=split(@intervall,stats.gets)
  allvalues << lastvalues[1]
  starttime=Time.at lastvalues[0].to_i
  starthour=Time.new(starttime.year,starttime.month,starttime.day).to_f/3600
  startcomment = sprintf("# Start at %04d-%02d-%02dT%02d:%02d:%02d with %d kWh",starttime.year,starttime.month,starttime.day,starttime.hour,starttime.min,starttime.sec,lastvalues[1].to_i)

  values=[0,0,0]
  nexttimepos=starttime.to_i + allvalues.size*@intervall
  stats.each_line do |line|
    values=split(@intervall,line)
    a=(values[1]-lastvalues[1])/(values[0]-lastvalues[0])
    # Überspringe solange die Werte bis wir Werte für das nächste Intervall erhalten
    while values[0]>=nexttimepos
      # Wir sind im nächsten Intervall oder noch weiter. Nun müssen wir den Zählerstand an den Intervallübergängen bestimmen
      allvalues << lastvalues[1]+a*(nexttimepos-lastvalues[0])
      nexttimepos=starttime.to_f + @intervall*allvalues.size
    end
    lastvalues=values
  end
  stats.close
  allvalues << lastvalues[1]
  total = allvalues.last-allvalues.first
  average = 3600*(total)/(@intervall*allvalues.size)

  # "allvalues" enthällt nun den (ansteigenden) Zählerstand (in kWh) an den Intervallpunkten
  # Nun bestimmen wir die erste Ableitung und errechnen pro Intervall den durchschnittlichen Verbauch in kW aus
  verbrauch=[]
  for t in 0 .. (allvalues.size-2)
    verbrauch << (allvalues[t+1]-allvalues[t])/@intervall_h
  end

  return starttime, startcomment, verbrauch, minvalue, maxvalue, average, total
end

if logpath==nil or logpath==""
  printf("No LOGPATH was defined.\n");
  exit
end
if logfiles==nil or logfiles==""
  printf("No LOGFILES were defined.\n");
  exit
end
if @outputfolder_image==nil or @outputfolder_image==""
  printf("No OUTPUTFOLDER for image was defined.\n");
  exit
end
if @outputfolder_text==nil or @outputfolder_text==""
  printf("No OUTPUTFOLDER for text was defined.\n");
  exit
end
if @intervall < 10
  printf("Intervall to small : %.1f < 10.0\n",@intervall)
  exit
end

durchschnittverbrauch=read_durchschnittverbrauch(@outputfolder_text+"/averagevalues.txt",@intervall)

Dir[logpath+"/"+logfiles].sort.each do |logfile|
  filebasename=File.basename(logfile,".csv")
  graphfile=@outputfolder_image+"/"+filebasename+".png"

  if File.exists? graphfile
    graphfile_l=File.stat(logfile).mtime.to_f
    graphfile_t=File.stat(graphfile).mtime.to_f
    if graphfile_l < graphfile_t
      printf("Skipping '%s'\n",logfile)
      next
    end
  end

  starttime, startcomment, verbrauch, minvalue, maxvalue, average, total = calculate_csv_file logfile

  # Füge den Verbrauch unserem Tagesdurchschnitt über die vergangen Tage hinzu
  if durchschnittverbrauch.size <= verbrauch.size
    if durchschnittverbrauch.size < verbrauch.size
      printf("data size is with %d to big. using only %d values for average calculation.\n",verbrauch.size,durchschnittverbrauch.size)
    end
    durchschnittverbrauch.map!{|x| x*0.95}
    durchschnittverbrauch=durchschnittverbrauch.zip(verbrauch.map{|x| x*0.05}).map{ |x| x.reduce(:+) }
  else
    printf("Skipping average calculation while data size %d is not to small. it should be %d.\n",verbrauch.size,durchschnittverbrauch.size)
  end

  tmpfile=File.new(@outputfolder_text+"/"+filebasename+".txt","w")
  tmpfile.puts startcomment
  writeplotdata(tmpfile,verbrauch,@intervall_h)

  # Bestimme Minumum und Maxiumum und deren Position
  (minvalue[1],maxvalue[1])=verbrauch[0..-2].minmax
  minvalue[0]=(verbrauch.find_index(minvalue[1])+0.5)*@intervall_h
  maxvalue[0]=(verbrauch.find_index(maxvalue[1])+0.5)*@intervall_h

  tmpfile.close

  io=IO.popen("gnuplot", "w")
  io << initgnuplot
  io << sprintf("set output '%s'\n",graphfile)
  io << sprintf("set title 'Verbrauch am %04d-%02d-%02d (%.1fkWh)'\n",starttime.year,starttime.month,starttime.day,total)
  io << sprintf("set label 'max %.0fW' at %f,%f center rotate front\n",maxvalue[1]*1000,maxvalue[0],maxvalue[1]/2)
  io << sprintf("set label 'min %.0fW' at %f,%f left rotate front\n",minvalue[1]*1000,minvalue[0],minvalue[1]*1.2)
  io << sprintf("plot '%s' t 'Gesamt' ls 1",tmpfile.path)
  io << ","
  io << sprintf("     %f t 'Durchschnitt %.0fW'",average,average*1000)
  io << ","
  io << sprintf("     %f t 'min %.0fW'",minvalue[1],minvalue[1]*1000)
  io << "\n"
  io.close
end

tmpfile=File.new(@outputfolder_text+"/averageday.txt","w")
writeplotdata(tmpfile,durchschnittverbrauch,@intervall_h)
tmpfile.close
average=durchschnittverbrauch.reduce(:+)/durchschnittverbrauch.size
io=IO.popen("gnuplot", "w")
io << initgnuplot
io << sprintf("set output '%s'\n",@outputfolder_image+"/tagesdurchschnitt.png")
io << sprintf("set title 'Tages Durchscnittsverbrauch (%.1fkWh)'\n",average*24.0)
io << sprintf("plot '%s' t 'Gesamt' ls 1",tmpfile.path)
io << ","
io << sprintf("     %f t 'Durchschnitt %.0fW'",average,average*1000)
io << "\n"
io.close

write_durchschnittverbrauch(@outputfolder_text+"/averagevalues.txt",durchschnittverbrauch)

File.delete(pidfile)
