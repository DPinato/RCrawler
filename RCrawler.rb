#!/usr/bin/ruby
# usage: ./RCrawler.rb <config_file>
require 'open-uri'
require 'date'
require 'thread'
require 'csv'
require 'logger'
require 'fileutils'		# so that I can use FileUtils.mkpath

load 'Operation.rb'
load 'Alerter.rb'


BEGIN {
  # this is called before the program is run
  puts "RCrawler is starting...\n"
  if ARGV.size == 0
    puts "Please specify config file"
    puts "Usage: ./RCrawler.rb <config_file>"
		puts "optional: -i <instance_id>"
    exit
  end
}

END {
  # this is called at the end of the program
  puts "\nRCrawler is ending..."
}



class Crawler

  def initialize(aObj, lObj, id=-1)
    @objId = id   # useful when using multiple threads
		@alertObj = aObj	# object used to send alerts
		@logObj = lObj		# object used to log stuff

		logObj.debug("thrId: #{@objId}, #{aObj.inspect}, #{lObj.inspect}")

  end


  def runPings(opInput)
    # run a ping every delay number of seconds
    @pingDelay = opInput.interval.to_i  # delay, in seconds, between ping commands
    @pingDest = opInput.dest.to_s    # destination IP address for ping
    @pingCounter = 0          # count how many pings have been taken, if -1 go on forever
    @pingLimit = opInput.reps.to_i        # number of pings to send
    @pingLatency = Array.new  # latency for ping
    @pingReturnEpoch = Array.new     	# date in which ping result was taken
		@pingReturnEpochDay = Array.new		# milliseconds after the start of the day in which ping result was taken
    @pingBaseOutputDir = opInput.outputDir.to_s # directory to store output files in
    @pingFileHeader = opInput.pingFileHeader.to_s    # static file headers to put at the top of an output file
    @pingOutFile
    @pingDstIsIP = false

    begin
      unless opInput.is_a?(Operation)
        raise "UnexpectedType"
      end

    rescue => e
      puts "runPings(...) is expecting an Operation object"
      puts "EXCEPTION, runPings(...): #{e}"
			logObj.error("thrId: #{@objId}, runPings(...): #{e}")
      return
    end


    # TODO: does checking for the correct IP address even matter, if I can also put in a hostname?
    num = "(\\d|[01]?\\d\\d|2[0-4]\\d|25[0-5])" # TODO: this will consider x.x.xxx as a valid IP address
    pat = "^(#{num}\.){3}#{num}$"
    ip_pat = Regexp.new(pat)

    # check if the input is a valid IP address or a hostname
    #puts pingDest
    if pingDest =~ ip_pat
      pingDstIsIP = true  # this should only run if pingDest is a valid IP address
    else
      pingDstIsIP = false
    end
    ######################################################################################################


    # create file to store data to
    pos1 = pingDest.index(":").to_i
    tmpStr = "ping_" + pingDest[pos1, pingDest.length - (pos1)]
    pingOutFile = pingBaseOutputDir + tmpStr + "_" + DateTime.now.strftime('%Q').to_s + ".log"
    puts "thrId: #{objId}, pingOutFile: #{pingOutFile.to_s}"
		logObj.debug("thrId: #{@objId}, pingOutFile: #{pingOutFile.to_s}")

    begin
      outFile = File.open(pingOutFile, 'w')
    rescue Errno::ENOENT
      puts "Could not write to pingOutFile: #{pingOutFile.to_s}"
			logObj.error("thrId: #{@objId}, Could not write to pingOutFile: #{pingOutFile.to_s}")
      return
    end

    # put first few lines of data to file
    outFile << "# PING\t" << pingDest << "\n"  # URL being crawled
    outFile << "# Started at: " << DateTime.now.to_s << "\n"
    outFile << pingFileHeader << "\n"


    # start the pings
    # stores a -1 if the ping does not succeeds, i.e. timeout
		failCounter = 0			# count how many times the operation failed
		alertSent = false		# flag whether the alert was sent for the last occurrence
    loop do
			tmpLatency = -1
      now = `ping #{pingDest.to_s} -c 1 -W 5000` # anything above 5 seconds is really high
																									# remember that Mac OS has that value in milliseconds
			#puts "now #{now.size}" + ": " + now.to_s

			# if now has no size, we could not resolve the hostname or something OS-related happened
			unless now.size == 0 || now.index("100.0% packet loss")
	      tmpStr = now.split("\n")[1] # get second line of output "64 bytes from 8.8.8.8: icmp_seq=1 ttl=59 time=13.7 ms"
	      index = tmpStr.rindex("time").to_i
				#puts "tmpStr: " + tmpStr
	      #puts "index: " + index.to_s

	      pos1 = index.to_i + "time".length.to_i + 1
	      tmpLatency = tmpStr[pos1, tmpStr.length - pos1 - 3]

				failCounter = 0
				alertSent = false
			else
				failCounter += 1
				logObj.debug("thrId: #{@objId}, #{pingDest.to_s} failCounter=#{failCounter}")

				#puts "FAILED, " + "#{failCounter}\t" + "#{alertObj.maxPingsBeforeAlert.to_i}"
				if failCounter >= alertObj.maxPingsBeforeAlert.to_i && !alertSent
					# send alert, but only one per-occurrence
					currEpoch = DateTime.now.strftime('%Q')	# this so that logs and email alert have the same timestamp
					alertObj.sendEmailAlert("PING", pingDest.to_s, failCounter, currEpoch.to_s, DateTime.strptime(currEpoch,'%Q'))
					alertSent = true
					puts "[#{currEpoch},#{objId.to_s}]: PING Alert sent, #{pingDest.to_s}"
					logObj.info("thrId: #{@objId}, PING Alert sent, #{pingDest.to_s}")

				end

			end

      # store data in the arrays
			pingLatency.push(tmpLatency)   # save current latency from ping command
      pingReturnEpoch.push(DateTime.now.strftime('%Q').to_s)  # save current epoch time in milliseconds, this is UTC+0
			pingReturnEpochDay.push(pingReturnEpoch[pingReturnEpoch.size-1].to_i % (3600000*24))

      # show something in the terminal
			pingOutput = objId.to_s + ", " + pingCounter.to_s + ", " + pingDest
			pingOutput += ", latency: #{pingLatency[pingLatency.size - 1].to_s} ms"
      puts pingOutput
			logObj.info("thrId: #{@objId}, #{pingOutput.to_s}")


      # save to file
      outFile << pingLatency[pingLatency.size-1]
      outFile << "\t" << pingReturnEpoch[pingReturnEpoch.size-1]
			outFile << "\t" << pingReturnEpochDay[pingReturnEpochDay.size-1]
      outFile << "\n"

			if pingCounter % 100 == 0
				logObj.debug("thrId: #{@objId}, clearing PING arrays...")
				pingLatency.clear
				pingReturnEpoch.clear
				pingReturnEpochDay.clear
			end


			# increase counters and see if the loop needs to continue
      self.pingCounter += 1

      if pingLimit > 0 && pingCounter >= pingLimit
				puts "thrId: #{@objId} has completed #{pingLimit} PING operations, #{pingDest}"
				logObj.info("thrId: #{@objId} has completed #{pingLimit} PING operations, #{pingDest}")
        break
      else
				sleep pingDelay
			end


    end

		outFile.close

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
		@httpReturnEpochDay = Array.new
    @httpBaseOutputDir = opInput.outputDir.to_s  # directory to store output files in
    @httpFileHeader = opInput.httpFileHeader.to_s    # static file headers to put at the top of an output file
    @httpOutFile


    # create file to store data to
    pos1 = httpUrl.index(":").to_i
    fileName = httpUrl[0,pos1] + "_" + httpUrl[pos1+3, httpUrl.length - (pos1+3)]
    httpOutFile = httpBaseOutputDir + fileName + "_" + DateTime.now.strftime('%Q').to_s + ".log"

    puts "id: #{objId}, httpOutFile: " + httpOutFile

    begin
      outFile = File.open(httpOutFile, 'w')
    rescue Errno::ENOENT
      puts "Could not write to httpOutFile: #{httpOutFile.to_s}"
			logObj.error("thrId: #{@objId}, Could not write to httpOutFile: #{httpOutFile.to_s}")
      return
    end


    # put first few lines of data to file
    outFile << "# HTTP\t" << httpUrl << "\n"  # URL being crawled
    outFile << "# Started at: " << DateTime.now.to_s << "\n"
    outFile << httpFileHeader << "\n"


    # start crawling
		failCounter = 0			# count how many times the operation failed
		alertSent = false		# flag whether the alert was sent for the last occurrence
		currEpoch = 0
    loop do
      startTime = DateTime.now.strftime('%Q').to_s

      begin
        queryResponse = open(httpUrl.to_s)

      # try to rescue from any exceptions, but keep trying
			# TODO: for some reason the rescue clauses below throw runtime errors on Mac OS
			rescue Exception => e
				# TODO: do some logging before re-raising the exception
				puts "#{e}"
				logObj.error("thrId: #{@objId}, runHttpQueries() #{e}")
				failCounter += 1
				logObj.debug("thrId: #{@objId}, #{httpUrl.to_s} failCounter=#{failCounter}")

				#puts "FAILED, " + "#{failCounter}\t" + "#{alertObj.maxPingsBeforeAlert.to_i}"
				if failCounter >= alertObj.maxHTTPBeforeAlert.to_i && !alertSent
					# send alert, but only one per-occurrence
					currEpoch = DateTime.now.strftime('%Q')	# this so that logs and email alert have the same timestamp
					alertObj.sendEmailAlert("HTTP", httpUrl.to_s, failCounter, currEpoch.to_s, DateTime.strptime(currEpoch,'%Q'))
					alertSent = true
					puts "[#{currEpoch},#{objId.to_s}]: HTTP Alert sent, #{httpUrl.to_s}"
					logObj.info("thrId: #{@objId}, HTTP Alert sent, #{httpUrl.to_s}")

				end

				#raise e  # TODO: re-raise exception previously ignored and process properly

			end


=begin
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
=end

			currEpoch = DateTime.now.strftime('%Q').to_s

			# if the query failed, save a whole bunch of -1s to file
			if failCounter > 0
				duration = -1
				responseStatus = -1
				responseBody = ""
			else
      	duration = currEpoch.to_i - startTime.to_i  # time taken to do the HTTP GET, in milliseconds
      	responseStatus = queryResponse.status     # HTTP response code received by the server
      	responseBody = queryResponse.read

				# reset flags and variables
				alertSent = false
				failCounter = 0
			end

      # store data in the arrays
      httpDuration.push(duration)
      httpReturnCode.push(responseStatus[0])
      httpReturnSize.push(responseBody.length)
      httpReturnEpoch.push(currEpoch)
			httpReturnEpochDay.push(httpReturnEpoch[httpReturnEpoch.size-1].to_i % (3600000*24))

			# show some output in the terminal
			httpOutput = "thrId: #{objId}" + ", " + httpCounter.to_s + ", " + httpUrl + ", " + duration.to_s + " ms"
			httpOutput += ", code: " + responseStatus[0].to_s + ", size: " + responseBody.length.to_s
      puts httpOutput
			logObj.info(httpOutput)


      # save to file
      outFile << httpDuration[httpDuration.size-1]
      outFile << "\t" << httpReturnCode[httpReturnCode.size-1]
      outFile << "\t" << httpReturnSize[httpReturnSize.size-1]
      outFile << "\t" << httpReturnEpoch[httpReturnEpoch.size-1]
			outFile << "\t" << httpReturnEpochDay[httpReturnEpochDay.size-1]
      outFile << "\n"

			if httpCounter % 100 == 0
				# store at most 100 elements in the arrays
				logObj.debug("thrId: #{@objId}, clearing HTTP arrays...")
				httpDuration.clear
				httpReturnCode.clear
				httpReturnSize.clear
				httpReturnEpoch.clear
				httpReturnEpochDay.clear
			end


			# increase counters and see if the loop needs to continue
      self.httpCounter += 1

      if httpLimit > 0 && httpCounter >= httpLimit
				puts "thrId: #{@objId} has completed #{httpLimit} HTTP operations, #{httpUrl}"
				logObj.info("thrId: #{@objId} has completed #{httpLimit} HTTP operations, #{httpUrl}")
        break
      else
				sleep httpDelay
			end

    end

    outFile.close


  end




  # accessors for instance variables
  attr_accessor :objId
	attr_accessor :alertObj
	attr_accessor :logObj

  attr_accessor :pingDelay
  attr_accessor :pingDest
  attr_accessor :pingCounter
  attr_accessor :pingLimit
  attr_accessor :pingLatency
  attr_accessor :pingReturnEpoch
	attr_accessor :pingReturnEpochDay
  attr_accessor :pingBaseOutputDir
  attr_accessor :pingFileHeader
  attr_accessor :pingOutFile
  attr_accessor :pingDstIsIP

  attr_accessor :httpUrl
  attr_accessor :httpDelay
  attr_accessor :httpCounter
  attr_accessor :httpLimit
  attr_accessor :httpDuration
  attr_accessor :httpReturnCode
  attr_accessor :httpReturnSize
  attr_accessor :httpReturnEpoch
	attr_accessor :httpReturnEpochDay
  attr_accessor :httpBaseOutputDir
  attr_accessor :httpFileHeader

end




# read config file and create the appropriate instance objects
tmpStatsDir = ""
tmpLogsDir = ""
tmpHttpFileHeader = ""
tmpPingFileHeader = ""
tmpAlertTemplateLocation = ""
tmpEmailAddresses = ""
tmpMaxPingsBeforeAlert = ""
tmpMaxHTTPBeforeAlert = ""
tmpOperationsPerInstance = -1

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

		# variables indicating directories where to save stuff
    if line.include?("statsDir")
      pos = line.index('=')
      tmpStatsDir = line[pos+1, line.size - (pos+1)].chomp!  # last character is newline
    end
		if line.include?("logsDir")
			pos = line.index('=')
			tmpLogsDir = line[pos+1, line.size - (pos+1)].chomp!  # last character is newline
		end

    if line.include?("httpFileHeader")
      pos = line.index('=')
      tmpHttpFileHeader = line[pos+1, line.size - (pos+1)].chomp!  # last character is newline
    end

    if line.include?("pingFileHeader")
      pos = line.index('=')
      tmpPingFileHeader = line[pos+1, line.size - (pos+1)].chomp!  # last character is newline
    end

    # read variables related to alerts
		if line.include?("alertTemplateLocation")
      pos = line.index('=')
      tmpAlertTemplateLocation = line[pos+1, line.size - (pos+1)].chomp!  # last character is newline
    end
    if line.include?("emailAddresses")  # TODO: add support for multiple email addresses
      pos = line.index('=')
      tmpEmailAddresses = line[pos+1, line.size - (pos+1)].chomp!  # last character is newline
    end
    if line.include?("maxPingsBeforeAlert")
      pos = line.index('=')
      tmpMaxPingsBeforeAlert = line[pos+1, line.size - (pos+1)].chomp!  # last character is newline
    end
    if line.include?("maxHTTPBeforeAlert")
      pos = line.index('=')
      tmpMaxHTTPBeforeAlert = line[pos+1, line.size - (pos+1)].chomp!  # last character is newline
    end

		# read variables related to instances
		if line.include?("operationsPerInstance")	# goes with the -i flag
      pos = line.index('=')
      tmpOperationsPerInstance = line[pos+1, line.size - (pos+1)].chomp!  # last character is newline
    end

    # read list of operations to perform
    if line[0,4].include?("HTTP") || line[0,4].include?("PING")
      # process these lines as if they were a CSV file
      # format is: <operation>,<destination>,<interval>,<reps>
      tmpArray = CSV.parse_line(line)
      tmpOps = Operation.new(tmpArray[0], tmpArray[1], tmpArray[2], tmpArray[3], tmpStatsDir, tmpHttpFileHeader, tmpPingFileHeader)
      ops.push(tmpOps)
    end

  end

end


# show some output on what was loaded from the config file
puts "I have " + ops.size.to_s + " operations to do"
ops.each do |op|
	#tmpStr = op.opType + ", " + op.dest + ", " + op.interval.to_s + ", " + op.reps.to_s
end

puts "tmpStatsDir: " + tmpStatsDir
puts "tmpLogsDir: " + tmpLogsDir
puts "tmpAlertTemplateLocation: " + tmpAlertTemplateLocation
puts "tmpEmailAddresses: " + tmpEmailAddresses
puts "tmpMaxPingsBeforeAlert: " + tmpMaxPingsBeforeAlert
puts "tmpMaxHTTPBeforeAlert: " + tmpMaxHTTPBeforeAlert
puts "tmpOperationsPerInstance: " + tmpOperationsPerInstance



# check if the -i flag was given through the CLI, indicating that RCrawler will be running in an instanced mode
tmpIIndex = ARGV.index("-i")
instanceId = 0
firstOp = 0
lastOp = ops.size

if tmpIIndex != nil
	instanceId = ARGV[tmpIIndex+1].to_i
	puts "instanceId: #{instanceId}"

	# compute startOp and endOp
	firstOp = instanceId * tmpOperationsPerInstance.to_i
	lastOp = firstOp + tmpOperationsPerInstance.to_i - 1

	# do some error detection
	if firstOp > ops.size
		puts "Not enough operations for my instanceId, ops: #{ops.size}, instanceId: #{instanceId}, tmpOperationsPerInstance: #{tmpOperationsPerInstance}"
		exit
	elsif lastOp >= ops.size
		lastOp = ops.size-1		# this instance will be doing less operations than the others
	end

end

puts "Doing operations from index " + "#{firstOp}" + " to " + "#{lastOp}"


# these objects will be referenced by all the threads running the operations
# initialise the Alerter object
tmpAlertObj = Alerter.new(tmpEmailAddresses, tmpMaxPingsBeforeAlert, tmpMaxHTTPBeforeAlert)
tmpAlertObj.readEmailTemplate(tmpAlertTemplateLocation)

# initialise the Logger object, store logs in a separate directory for every instance
# TODO: make it possible to select in config file: number of old logs to keep, maximum log file size, logging level
#logFile = File.open(tmpLogsDir + "hehe.log", File::WRONLY | File::APPEND | File::CREAT)
logFileDir = tmpLogsDir + instanceId.to_s + "/"
unless Dir.exist?(logFileDir)
	begin
		#Dir.mkdir(logFileDir)
		FileUtils.mkpath(logFileDir)	# if needed, this will create every single directory that does not exist yet, so that
																	# the path will be created

	rescue SystemCallError
		puts "Could not create directory for log file, instance: #{instanceId.to_s}, exiting..."
		exit
	end
end

tmpLoggerObj = Logger.new(logFileDir + "hehe.log", 10, 1*1024*1024)
# DEBUG < INFO < WARN < ERROR < FATAL < UNKNOWN
tmpLoggerObj.level = Logger::DEBUG
tmpLoggerObj.info("Logger has started")

tmpLoggerObj.info("instanceId: #{instanceId}")
tmpLoggerObj.info("I have " + ops.size.to_s + " operations to do")

tmpLoggerObj.info("tmpStatsDir: " + tmpStatsDir)
tmpLoggerObj.info("tmpLogsDir: " + tmpLogsDir)
tmpLoggerObj.info("tmpAlertTemplateLocation: " + tmpAlertTemplateLocation)
tmpLoggerObj.info("tmpEmailAddresses: " + tmpEmailAddresses)
tmpLoggerObj.info("tmpMaxPingsBeforeAlert: " + tmpMaxPingsBeforeAlert)
tmpLoggerObj.info("tmpMaxHTTPBeforeAlert: " + tmpMaxHTTPBeforeAlert)
tmpLoggerObj.info("tmpOperationsPerInstance: " + tmpOperationsPerInstance)

tmpLoggerObj.info("Doing operations from index " + "#{firstOp}" + " to " + "#{lastOp}")




# create an array containing the threads that will run what is specified in the config file
# start the threads
crawlArray = Array.new

#threadArray = (0...ops.size).map do |i| # this is equivalent to for (int i = 0; i < ops.size() i++)
threadArray = (firstOp..lastOp).map do |i|

  crawlArray[i] = Crawler.new(tmpAlertObj, tmpLoggerObj, i)

  Thread.new(i) do |i|
    if ops[i].opType == "PING"
      crawlArray[i].runPings(ops[i])
    elsif ops[i].opType == "HTTP"
      crawlArray[i].runHttpQueries(ops[i])
    else
      puts "I do not understand operation: " + ops[i].opType
			tmpLoggerObj.error("I do not understand operation: " + ops[i].opType)
    end

  end
end

tmpLoggerObj.info("Starting #{threadArray.size} threads...")
threadArray.each {|t| t.join}
