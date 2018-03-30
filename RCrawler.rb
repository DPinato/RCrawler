#!/usr/bin/ruby
# usage: ./RCrawler.rb <config_file>
require 'open-uri'
require 'date'
require 'thread'
require 'csv'


BEGIN {
  # this is called before the program is run
  puts "RCrawler is starting...\n"
  if ARGV.size == 0
    puts "Please specify config file"
    puts "Usage: ./RCrawler.rb <config_file>"
    exit
  end
}

END {
  # this is called at the end of the program
  puts "\nRCrawler is ending..."
}



class Crawler

  def initialize(id=-1)
    @objId = id   # useful when using multiple threads
  end


  def runPings(dst, delay = 0, limit=-1)
    # run a ping every delay number of seconds
    @pingDelay = delay        # delay, in seconds, between ping commands
    @pingDestination = dst    # destination IP address for ping
    @pingCounter = 0          # count how many pings have been taken, if -1 go on forever
    @pingLimit = limit        # number of pings to send
    @pingLatency = Array.new  # latency for ping
    @pingDate = Array.new     # date in which ping result was taken


    num = "(\\d|[01]?\\d\\d|2[0-4]\\d|25[0-5])" # TODO: this will consider x.x.xxx as a valid IP address
    pat = "^(#{num}\.){3}#{num}$"
    ip_pat = Regexp.new(pat)

    # check if the IP address is valid
    begin
      puts pingDestination
      unless pingDestination =~ ip_pat
        raise "Bad IP Address"
      end

    rescue => e   # if the IP address is invalid, just return
      puts "EXCEPTION: #{e}"
      return
    end

    # start the pings
    # TODO: if the ping does not succeed, for whatever reason, this currently does not return anything
    loop do
      now = `ping #{dst} -c 1`

      tmpStr = now.split("\n")[1] # get second line of output "64 bytes from 8.8.8.8: icmp_seq=1 ttl=59 time=13.7 ms"
#      puts tmpStr

      index = tmpStr.rindex("time")
      pos1 = index + "time".length + 1

      # store data in the arrays
      pingDate.push(Time.now.to_i)  # set current epoch time in seconds
      pingLatency.push(tmpStr[pos1, tmpStr.length - pos1 - 3])   # set current latency from ping command

      # show something in the terminal
      puts "Latency: " + pingLatency[pingLatency.size - 1] + " ms"


      self.pingCounter += 1
      sleep pingDelay

      # stop if the number of pings was reached
      if pingLimit > 0 && pingCounter >= pingLimit
        break
      end

    end

  end


  #def runHttpQueries(url, delay=10, limit=-1)
  def runHttpQueries(opInput)
    # run a get query for the URL every interval number of seconds
    # take as input an Operation object containing all the necessary values
    # make sure that opInput is an Operation object
    begin
      unless opInput.is_a?(Operation)
        raise "UnexpectedType"
      end

    rescue => e
      puts "runHttpQueries(...) is expecting an Operation object"
      puts "EXCEPTION: #{e}"
      return

    end

    @httpUrl = opInput.dest.to_s    # this NEEDS to start with either http:// or https://, otherwise it will be
                                    # interpreted as the location of a local file
    @httpDelay = opInput.interval.to_i
    @httpCounter = 0
    @httpLimit = opInput.reps.to_i
    @httpDuration = Array.new
    @httpReturnCode = Array.new
    @httpReturnSize = Array.new
    @httpReturnEpoch = Array.new
    @httpBaseOutputDir = opInput.outputDir.to_s  # directory to store output files in
    @httpFileHeader = opInput.outFileHeader.to_s    # static file headers to put at the top of an output file
    @httpOutFile


    # create file to store data to
    pos1 = httpUrl.index(":").to_i
    tmpStr = httpUrl[pos1+3, httpUrl.length - (pos1+3)]
    httpOutFile = httpBaseOutputDir + tmpStr + "_" + DateTime.now.strftime('%Q').to_s + ".log"

    puts "id: #{objId}, httpOutFile: " + httpOutFile

    begin
      outFile = File.open(httpOutFile, 'w')
    rescue Errno::ENOENT
      puts "Could not write to httpOutFile: " + httpOutFile
      return
    end


    # put first few lines of data to file
    outFile << "# " << httpUrl << "\n"  # URL being crawled
    outFile << "# " << DateTime.now.to_s << "\n"
    outFile << httpFileHeader << "\n"


    # start crawling
    loop do
      startTime = DateTime.now.strftime('%Q').to_s

      begin
        queryResponse = open(httpUrl.to_s)

      # try to rescue from any exceptions, but keep trying
      rescue SocketError
        # something happened to the socket, can happen when adapter is turned off or if could not
        # resolve domain name for URL
        puts "SocketError, #{httpUrl}"
        sleep httpDelay
        retry

      rescue Net::OpenTimeout
        puts "Net::OpenTimeout, #{httpUrl}"
        sleep httpDelay
        retry

      rescue Exception => e
        # use this as a catch-all scenario
        puts "Uncaught exception: #{e}, #{httpUrl}"
        sleep httpDelay
        retry

      end

      endTime = DateTime.now.strftime('%Q').to_s
      duration = endTime.to_i - startTime.to_i  # time taken to do the HTTP GET, in milliseconds
      responseStatus = queryResponse.status     # HTTP response code received by the server
      responseBody = queryResponse.read

      # store data in the arrays
      httpDuration.push(duration)
      httpReturnCode.push(responseStatus[0])
      httpReturnSize.push(responseBody.length)
      httpReturnEpoch.push(endTime)

      # save to file
      outFile << httpDuration[httpDuration.size-1]
      outFile << "\t" << httpReturnCode[httpReturnCode.size-1]
      outFile << "\t" << httpReturnSize[httpReturnSize.size-1]
      outFile << "\t" << httpReturnEpoch[httpReturnEpoch.size-1]
      outFile << "\n"


      # show some output in the terminal
      print objId.to_s + "\t" + httpUrl
      print "\t" + duration.to_s + " ms"
      print "\tcode: " + responseStatus[0]
      print "\tsize: " + responseBody.length.to_s
      print "\tepoch: " + endTime
      print "\n"


      self.httpCounter += 1
      sleep httpDelay

      # stop if the number of queries was reached
      if httpLimit > 0 && httpCounter >= httpLimit
        break
      end



    end

    # loop is over
    outFile.close


  end




  # accessors for instance variables
  attr_accessor :objId

  attr_accessor :pingDelay
  attr_accessor :pingDestination
  attr_accessor :pingCounter
  attr_accessor :pingLimit
  attr_accessor :pingLatency
  attr_accessor :pingDate

  attr_accessor :httpUrl
  attr_accessor :httpDelay
  attr_accessor :httpCounter
  attr_accessor :httpLimit
  attr_accessor :httpDuration
  attr_accessor :httpReturnCode
  attr_accessor :httpReturnSize
  attr_accessor :httpReturnEpoch
  attr_accessor :httpBaseOutputDir
  attr_accessor :httpFileHeader

end


class Operation
# class used to store input from the config file
# TODO: probably a struct would be better here

  def initialize(opType, dest, interval, reps, outputDir, outFileHeader)
    @opType = opType
    @dest = dest
    @interval = interval
    @reps = reps
    @outputDir = outputDir
    @outFileHeader = outFileHeader
  end

  attr_accessor :opType
  attr_accessor :dest
  attr_accessor :interval
  attr_accessor :reps
  attr_accessor :outputDir
  attr_accessor :outFileHeader
end


# read config file and create the appropriate instance objects
tmpOutputDir = ""
tmpFileHeader = ""
ops = Array.new

begin
  confFile = File.open(ARGV[0], 'r')

rescue => e
  # I do not really want to rescue anything here, since it will most likely happen due to issues
  # opening the config file
  puts "#{e}"
  exit
end

confFile.readlines().each do |line|

  # lines beginning with '#' in the config file, are used as a comment
  unless line.size < 3 || line[0] == '#'
#    print "#{line}"

    if line.include?("outputDir")
      pos = line.index('=')
      tmpOutputDir = line[pos+1, line.size - (pos+1)].chomp!  # last character is newline
      # puts "tmpOutputDir: " + tmpOutputDir
    end

    if line.include?("fileHeader")
      pos = line.index('=')
      tmpFileHeader = line[pos+1, line.size - (pos+1)].chomp!  # last character is newline
      #puts "tmpFileHeader: " + tmpFileHeader
    end


    if line.include?("HTTP") || line.include?("PING")
      # process these lines as if they were a CSV file
      # format is: <operation>,<destination>,<interval>,<reps>
      tmpArray = CSV.parse_line(line)
      tmpOps = Operation.new(tmpArray[0], tmpArray[1], tmpArray[2], tmpArray[3], tmpOutputDir, tmpFileHeader)
      ops.push(tmpOps)
    end

  end

end


# show some output on what was loaded from the config file
puts "I have " + ops.size.to_s + " operations to do"
ops.each do |op|
  puts op.opType + "\t" + op.dest + "\t" + op.interval.to_s + "\t" + op.reps.to_s
end




# create an array containing the threads that will run what is specified in the config file
crawlArray = Array.new

threadArray = (0...ops.size).map do |i| # this is equivalent to for (int i = 0; i < ops.size() i++)
  crawlArray[i] = Crawler.new(i)

  Thread.new(i) do |i|
    crawlArray[i].runHttpQueries(ops[i])
  end
end

threadArray.each {|t| t.join}







=begin
t1 = Thread.new{crawlArray[0].runHttpQueries(ops[0])}
t2 = Thread.new{crawlArray[1].runHttpQueries(ops[1])}
t1.join
t2.join
=end


=begin
for i in 0...ops.size
  puts crawlArray[i].httpUrl

end

# start the threads
for i in 0...threadArray.size
  threadArray[i].join
end
=end



=begin
testCrawler = Crawler.new(1)
testCrawler.runPings(2, "216.58.205.110")


# put the crawlers in different threads
t1 = Thread.new{crawl1.runHttpQueries("https://yahoo.com", 720, 10)}
t2 = Thread.new{crawl2.runHttpQueries("https://twitch.tv", 720, 10)}
t3 = Thread.new{crawl3.runHttpQueries("https://youtube.com", 720, 10)}
t4 = Thread.new{crawl4.runHttpQueries("https://stackoverflow.com", 720, 10)}

t1.join
t2.join
t3.join
t4.join
=end
