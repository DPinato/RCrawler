#!/usr/bin/ruby
# usage: ./RCrawler.rb <config_file>
require 'open-uri'
require 'date'
require 'thread'
require 'csv'
require 'logger'
require 'fileutils'		# so that I can use FileUtils.mkpath
require 'influxdb'
require 'open3'
require 'HTTParty'

load 'Operation.rb'
load 'Alerter.rb'
load 'Crawler.rb'


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



# read config file and create the appropriate instance objects
tmpLogsDir = ""
tmpHttpFileHeader = ""
tmpSendAlerts = ""
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
		# print "#{line}"

		# read variables from config file
		if line.include?("logsDir")
			pos = line.index('=')
			tmpLogsDir = line[pos+1, line.size - (pos+1)].chomp!  # last character is newline
		end

    if line.include?("httpFileHeader")
      pos = line.index('=')
      tmpHttpFileHeader = line[pos+1, line.size - (pos+1)].chomp!  # last character is newline
    end

    # read variables related to alerts
		if line.include?("sendAlerts")
			pos = line.index('=')
			tmpSendAlerts = line[pos+1, line.size - (pos+1)].chomp!  # last character is newline
			if tmpSendAlerts == "true"
				tmpSendAlerts = true
			elsif tmpSendAlerts == "false"
				tmpSendAlerts = false
			else
				puts "Bad sendAlerts value in config file"
			end
		end
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
      tmpOps = Operation.new(tmpArray[0], tmpArray[1], tmpArray[2], tmpArray[3], tmpHttpFileHeader)
      ops.push(tmpOps)
    end

  end

end


# show some output on what was loaded from the config file
puts "I have " + ops.size.to_s + " operations to do"
ops.each do |op|
	#tmpStr = op.opType + ", " + op.dest + ", " + op.interval.to_s + ", " + op.reps.to_s
end

puts "tmpLogsDir: " + tmpLogsDir
puts "tmpSendAlerts: #{tmpSendAlerts}"
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
tmpAlertObj = Alerter.new(tmpEmailAddresses, tmpMaxPingsBeforeAlert, tmpMaxHTTPBeforeAlert, tmpSendAlerts)
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
tmpLoggerObj.info("tmpLogsDir: " + tmpLogsDir)
tmpLoggerObj.info("tmpAlertTemplateLocation: " + tmpAlertTemplateLocation)
tmpLoggerObj.info("tmpEmailAddresses: " + tmpEmailAddresses)
tmpLoggerObj.info("tmpMaxPingsBeforeAlert: " + tmpMaxPingsBeforeAlert)
tmpLoggerObj.info("tmpMaxHTTPBeforeAlert: " + tmpMaxHTTPBeforeAlert)
tmpLoggerObj.info("tmpOperationsPerInstance: " + tmpOperationsPerInstance)

tmpLoggerObj.info("Doing operations from index " + "#{firstOp}" + " to " + "#{lastOp}")


# connect to the influxdb instance and create the database
dbName = "RCrawler"		# database name
nameSeries = "test"
dbHost = "localhost"

puts "Connecting to influxDB at #{dbHost}..."
tmpLoggerObj.info("Connecting to influxDB at #{dbHost}...")
influxdb = InfluxDB::Client.new(dbName, host: dbHost, time_precision: "ms")

puts "Creating DB #{dbName} ..."
tmpLoggerObj.info("Creating DB #{dbName} ...")
influxdb.create_database(dbName)	# create influxdb database for RCrawler



# create an array containing the threads that will run what is specified in the config file
crawlArray = Array.new

#threadArray = (0...ops.size).map do |i| # this is equivalent to for (int i = 0; i < ops.size() i++)
threadArray = (firstOp..lastOp).map do |i|

  crawlArray[i] = Crawler.new(tmpAlertObj, tmpLoggerObj, influxdb, i)

  Thread.new(i) do |i|
    if ops[i].opType == "PING"
      crawlArray[i].runPings(ops[i])
    elsif ops[i].opType == "HTTP"
      crawlArray[i].runHttpQueries(ops[i])
    else
      puts "I do not understand operation: #{ops[i].opType}"
			tmpLoggerObj.error("I do not understand operation: #{ops[i].opType}")
    end
  end
end

# start the threads
tmpLoggerObj.info("Starting #{threadArray.size} threads...")
threadArray.each {|t| t.join}
