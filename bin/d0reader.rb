#!/usr/bin/env ruby

require 'socket'
require 'rexml/document'

class TimeAverage
  def initialize(damping=100)
    @damping=damping
    @timestamp=Time.now.to_f
    @average=0
    @lastvalue=nil
    @lastaverage=@average
  end

  def add(value)
    if @lastvalue == nil
      @lastvalue = value
    end
    t = Time.now.to_f
    v = 3600000 * (value-@lastvalue).to_f / (t-@timestamp).to_f
    @average = (@average*@damping+v).to_f / (@damping+1).to_f
    @timestamp=t
    @lastvalue=value
  end

  def get
    @lastaverage=@average.round
    return @average
  end

  def to_s
    @lastaverage=@average.round
    return sprintf("%0.1f\t%1.0f",@timestamp,@average)
  end

  def modified?
    return @lastaverage != @average.round
  end
end

def get_csvfilename(id,time)
  return sprintf("%s/%s_%s_%04d%02d%02d.csv",@logpath,@logprefix,id,time.year,time.mon,time.mday)
end

configfile="/etc/d0reader.xml"
obis = {}
@logpath = ""
@logprefix = ""
lesekopf = ""
pidfile = ""
intervall = 0
damping=50
d0mirrorPort=2000
averageOutPort=2001
@lastvalue = {}
@write2pipe = false
solarviewtcpserver=nil
@lastsolardata=nil

if File.exists? configfile
  config = REXML::Document.new File.new(configfile)
  if config == nil
    print("Parsing Error during reading configfile '%s'",configfile)
    exit
  end
  config=config.root
  config.elements.each("./OBIS") { |o| obis[o.attributes["id"]]={"alias"=>o.attributes["alias"],"comment"=>o.attributes["comment"]} } 
  config.elements.each("./LOGPATH") { |p| @logpath = p.text }
  config.elements.each("./LOGPREFIX") { |f| @logprefix = f.text }
  config.elements.each("./READER/LESEKOPF") { |f| lesekopf = f.text }
  config.elements.each("./READER/PIDFILE") { |f| pidfile = f.text }
  config.elements.each("./READER/INTERVAL") { |f| intervall = f.text.to_i }
  config.elements.each("./READER/LISTENPORT") do |f|
    d0mirrorPort = f.attributes["d0mirror"].to_i
    averageOutPort = f.attributes["average"].to_i
  end
  config.elements.each("./READER/DAMPING") { |f| damping = f.text.to_f }
  config.elements.each("./READER/SOLARVIEWTCPSERVER") { |f| solarviewtcpserver = [f.attributes["addr"],f.attributes["port"].to_i] }
else
  printf("No configfile '%s' found.\n",configfile)
  exit
end

# Pruefe, ob die Hash-Tabelle 'obis' korrekt initialisiert ist
# zu jeder ID muss es einen nicht leeren Alias geben.
obis.each do |id,values|
  if not values.has_key?("alias")
    printf("The id '%s' does not have set an alias!",id)
    exit
  end
  if values["alias"].size < 3
    printf("The alias '%s' of the id '%s' is to small!",values["alias"],id)
    exit
  end
end

def shut_down
  time=Time.now
  @lastvalue.each do |id,value|
    filename = get_csvfilename(id,time)
    log=File.open(filename,"a")
    log << sprintf("%.1f",time.to_f)
    log << "\t"
    log << value[0]
    log << "\n"
    log.close
  end
end

# Trap ^C
Signal.trap("INT") {
  shut_down
  exit
}
 
# Trap `Kill `
Signal.trap("TERM") {
  shut_down
  exit
} 

Signal.trap("HUP") {
  shut_down
} 

Signal.trap("USR1") {
  @write2pipe = true
} 
Signal.trap("USR2") {
  @write2pipe = false
} 

system "stty -F "+lesekopf+" 9600 evenp -cstopb"
system "mkdir -p "+@logpath

reader,writer = IO.pipe
averageNetIn=TimeAverage.new(damping)
averageNetOut=TimeAverage.new(damping)
averageSolar=0

pid1=fork do
  reader.close
  Thread.new do
    serv = TCPServer.new(averageOutPort)
    loop do
      sock = serv.accept
      sock.puts averageNetIn
      sock.puts averageNetOut
      sock.puts sprintf("%0.1f\t%1.0f",Time.now.to_f,averageSolar)
      sock.close
    end
  end
  File.open(lesekopf, "r").each_line do |line|
    if @write2pipe
      writer.write line
    end
    id=line.slice!(/^[-*:.0-9]*\(/)
    if id and id.size > 3
      id.slice!(-1)
      if obis.has_key?(id)
        id=obis[id]["alias"]
      end
      value=line.slice!(/[^)]*/)
      if value
        time=Time.now
        filename = get_csvfilename(id,time)
        if not File.exist?(filename)
          @lastvalue={}
        end
        t=(time.to_f/intervall.to_f).to_i
        if not ( @lastvalue.has_key?(id) and ( @lastvalue[id][0]==value or @lastvalue[id][1]==t ) )
          @lastvalue[id]=[value,t]
          log=File.open(filename,"a")
          log << sprintf("%.1f",time.to_f)
          log << "\t"
          log << value
          log << "\n"
          log.close
        end
        if id == "esy-counter-t1"
          averageNetIn.add value.to_f
          if solarviewtcpserver
            Thread.new do
              Socket.tcp("127.0.0.1", 15503) do |sock|
                sock.print "00*\n"
                sock.close_write
                solardata = sock.gets.slice(/{.*}/)[1..-2].split(",")
                # Erster Wert ist immer 0, daher nicht interessant und kann daher weg.
                solardata.shift
                t = solardata.shift(5).map{|v| v.to_i}
                t=Time.new t[2],t[1],t[0],t[3],t[4]
                solardata.map!{|v| v.to_f}
                solardata.unshift (t.to_f/intervall.to_f).to_i
                averageSolar = (averageSolar*damping+solardata[5]).to_f / (damping+1).to_f
                filename = get_csvfilename("solar",t)
                if not File.exist?(filename)
                  @lastsolardata = nil
                end
                if @lastsolardata == nil or ( @lastsolardata[0] != solardata[0] and @lastsolardata[1] != solardata[1] )
                  log=File.open(filename,"a")
                  log.puts sprintf("%.1f\t%f",t.to_f,solardata[1])
                  log.close
                  @lastsolardata = solardata
                end
              end
            end
          end
        end
      end
    end
  end
end
pid2=fork do
  writer.close
  Socket.tcp_server_loop(d0mirrorPort) {|sock, client_addrinfo|
#   puts sprintf("Connection opened from %s:%d",client_addrinfo.ip_address,client_addrinfo.ip_port)
    Process.kill("USR1", pid1)
    begin
      while message = reader.gets
        if sock.closed?
          break
        end
        sock.write message
      end
    rescue
#     puts sprintf("Connection closed from %s:%d",client_addrinfo.ip_address,client_addrinfo.ip_port)
      Process.kill("USR2", pid1)
    ensure
      sock.close
    end
  }
end

pidfile=File.open(pidfile,"w")
pidfile << pid1
pidfile << "\n"
pidfile << pid2
pidfile << "\n"
pidfile.close
