class Crawler

  def initialize(aObj, lObj, dbObj, id=-1)
		# aObj: reference to Alert object
		# lObj: reference to Logger object
		# dbObj: reference to influxdb object
		# id: useful when using multiple threads
    @objId, @alertObj, @logObj, @influxDBObj = id, aObj, lObj, dbObj
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
    ###############################################################################################

    # start the pings
    # stores a -1 if the ping does not succeeds, i.e. timeout
		failCounter = 0			# count how many times the operation failed
		alertSent = false		# flag whether the alert was sent for the last occurrence
    loop do
			tmpLatency = -1.0

			# anything above 5 seconds timeout is really high
			# remember that Mac OS has that value in milliseconds
			pingCmd = "ping #{pingDest.to_s} -c 1 -W 5000"
      # now = `ping #{pingDest.to_s} -c 1 -W 5000`

			stdout, stderr, status = Open3.capture3("#{pingCmd}")
			# puts "stdout: #{stdout}"
			# puts "stderr: #{stderr}"
			# puts "status: #{status}"
			# puts status.exitstatus


			# if now has no size, we could not resolve the hostname or something OS-related happened
			if stderr.size == 0
	      tmpStr = stdout.split("\n")[1] # get second line of output "64 bytes from 8.8.8.8: icmp_seq=1 ttl=59 time=13.7 ms"
	      index = tmpStr.rindex("time").to_i
	      pos1 = index.to_i + "time".length.to_i + 1
	      tmpLatency = tmpStr[pos1, tmpStr.length - pos1 - 3].to_f	# make it a float right here
				tmpTimestamp = DateTime.now.strftime('%Q').to_i

				# reset alert variables
				failCounter = 0
				alertSent = false

			else
				failCounter += 1
				logObj.debug("thrId: #{@objId}, #{pingDest.to_s} failCounter=#{failCounter}, exitstatus=#{status.exitstatus}")

				# check if alert needs to be sent
				if alertObj.sendAlerts && (failCounter >= alertObj.maxPingsBeforeAlert.to_i && !alertSent)
					# send alert, but only one per-occurrence
					currEpoch = DateTime.now.strftime('%Q')	# this so that logs and email alert have the same timestamp
					alertObj.sendEmailAlert("PING", pingDest.to_s, failCounter, currEpoch.to_s, DateTime.strptime(currEpoch,'%Q'))
					alertSent = true
					puts "[#{currEpoch},#{objId.to_s}]: PING Alert sent, #{pingDest.to_s}"
					logObj.info("thrId: #{@objId}, PING Alert sent, #{pingDest.to_s}")

				end
			end


			# store data in influxDB
			data = {
				values: {latency: tmpLatency, exitStatus: status.exitstatus},
				timestamp: tmpTimestamp,
			}
			influxDBObj.write_point("PING_"+pingDest.to_s, data)


      # show something in the terminal
			pingOutput = objId.to_s + ", " + pingCounter.to_s + ", " + pingDest
			pingOutput += ", latency: #{tmpLatency.to_s} ms"
			pingOutput += ", code: #{status.exitstatus}"
      puts pingOutput
			logObj.info("thrId: #{@objId}, #{pingOutput.to_s}")


			# increase counters and see if the loop needs to continue
      @pingCounter += 1
      if pingLimit > 0 && pingCounter >= pingLimit
				puts "thrId: #{@objId} has completed #{pingLimit} PING operations, #{pingDest}"
				logObj.info("thrId: #{@objId} has completed #{pingLimit} PING operations, #{pingDest}")
        break
      else
				sleep pingDelay
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


			#
      # rescue SocketError
      #   # something happened to the socket, can happen when adapter is turned off or if could not
      #   # resolve domain name for URL
      #   puts "SocketError, #{httpUrl}"
      #   sleep httpDelay
      #   retry
			#
      # rescue Net::OpenTimeout
      #   puts "Net::OpenTimeout, #{httpUrl}"
      #   sleep httpDelay
      #   retry
			#
      # rescue Exception => e
      #   # use this as a catch-all scenario
      #   puts "Uncaught exception: #{e}, #{httpUrl}"
      #   sleep httpDelay
      #   retry
			#
      # end


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
      @httpCounter += 1

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
  attr_accessor :objId, :alertObj, :logObj, :influxDBObj

  attr_accessor :pingDelay, :pingDest, :pingCounter, :pingLimit, :pingLatency, :pingReturnEpoch, :pingReturnEpochDay, :pingFileHeader, :pingDstIsIP

  attr_accessor :httpUrl, :httpDelay, :httpCounter, :httpLimit, :httpDuration, :httpReturnCode, :httpReturnSize, :httpReturnEpoch, :httpReturnEpochDay, :httpBaseOutputDir, :httpFileHeader

end
