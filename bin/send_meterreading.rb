#!/usr/bin/env ruby

require 'rexml/document'
require 'net/smtp'

configfile="/etc/d0reader.xml"
logpath=""
files=[]
mail_from=[]
mail_to=[]
mail_subject=""
mail_server="127.0.0.1"

def mail_addr_to_s(mail)
  ret=[]
  mail.each do |a|
    ret << sprintf("%s <%s>",a[0],a[1])
  end
  return ret.join(", ")
end

if File.exists? configfile
  config = REXML::Document.new File.new(configfile)
  if config == nil
    print("Parsing Error during reading configfile '%s'",configfile)
    exit
  end
  config=config.root
  config.elements.each("./LOGPATH") { |p| logpath = p.text }
  config.elements.each("./REPORT/FILE") { |p| files << [p.text,p.attributes["name"]] }
  config.elements.each("./MAIL/FROM") { |p| mail_from << [p.attributes["name"],p.attributes["address"]] }
  config.elements.each("./MAIL/TO") { |p| mail_to << [p.attributes["name"],p.attributes["address"]] }
  config.elements.each("./MAIL/SUBJECT") { |p| mail_subject = p.text }
  config.elements.each("./MAIL/SERVER") { |p| mail_server = p.text }
else
  printf("No configfile '%s' found.\n",configfile)
  exit
end

class String
  def is_integer?
    true if Integer(self) rescue false
  end
  def is_float?
    true if Float(self) rescue false
  end
end

time=Time.now
monthname=["0","Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
gmtoffset=time.gmt_offset
gmtoffsetsign="+"
if gmtoffset < 0
  gmtoffset=-gmtoffset
  gmtoffsetsign="-"
end
gmtoffsethour=gmtoffset/3600
gmtoffsetmin=gmtoffset/60-gmtoffsethour*60

message =  sprintf("From: %s\n",mail_addr_to_s(mail_from))
message << sprintf("To: %s\n",mail_addr_to_s(mail_to))
message << sprintf("Subject: %s\n",mail_subject)
message << sprintf("Date: %02d %s %04d %02d:%02d:%02d %s%02d%02d\n",time.day,monthname[time.month],time.year,time.hour,time.min,time.sec,gmtoffsetsign,gmtoffsethour,gmtoffsetmin)
message << "Content-Type: text/plain; charset=\"utf-8\"\n"
message << "Content-Transfer-Encoding: 8bit\n"
message << "\n"

message << sprintf("%20s : %02d.%02d.%04d\n","Datum",time.day,time.month,time.year)
files.each do |file|
  logfile = Dir[logpath+"/"+file[0]].sort.last
  lastentry=IO.readlines(logfile)[-1].split("\t")[1]
  if lastentry.is_integer?
    message << sprintf("%20s : %d\n",file[1],lastentry.to_i)
  elsif lastentry.is_float?
    message << sprintf("%20s : %.0f\n",file[1],lastentry.to_f)
  else
    message << sprintf("%20s : %s\n",file[1],lastentry.chop)
  end 
end

Net::SMTP.start(mail_server) do |smtp|
  smtp.send_message message, mail_from.first[1], mail_from.first[1], mail_to.map{|a| a[1]}
end
