#!/usr/bin/env ruby

require 'socket'
require 'rexml/document'

configfile="/etc/d0reader.xml"
obis = {}
@logpath = ""
@logprefix = ""
lesekopf = ""
pidfile = ""
intervall = 0
tcpserverport=2000
@lastvalue = {}
@write2pipe = false

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
  config.elements.each("./READER/LISTENPORT") { |f| tcpserverport = f.text.to_i }
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
    filename=sprintf("%s/%s_%s_%04d%02d%02d.csv",@logpath,@logprefix,id,time.year,time.mon,time.mday)
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

pid1=fork do
  reader.close
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
        filename=sprintf("%s/%s_%s_%04d%02d%02d.csv",@logpath,@logprefix,id,time.year,time.mon,time.mday)
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
      end
    end
  end
end

pid2=fork do
  writer.close
  Socket.tcp_server_loop(tcpserverport) {|sock, client_addrinfo|
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
