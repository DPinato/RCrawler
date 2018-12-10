# class implements the operations


class Crawler

  def initialize(aObj, lObj, dbObj, id=-1)
		# aObj: reference to Alert object
		# lObj: reference to Logger object
		# dbObj: reference to influxdb object
		# id: useful when using multiple RCrawler processes
    @objId, @alertObj, @logObj, @influxDBObj = id, aObj, lObj, dbObj
		logObj.debug("thrId: #{@objId}, #{aObj.inspect}, #{lObj.inspect}")

		@failCounter = 0
		@alertSent = false

  end


  def runPings(opInput)
    # run a ping every delay number of seconds
    @pingDelay = opInput.interval.to_i  # delay, in seconds, between ping commands
    @pingDest = opInput.dest.to_s    # destination IP address for ping
    @pingCounter = 0          # count how many pings have been taken, if -1 go on forever
    @pingLimit = opInput.reps.to_i        # number of pings to send
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
    loop do
			tmpLatency = -1.0

			# anything above 5 seconds timeout is really high
			# remember that Mac OS has that value in milliseconds
			pingCmd = "ping #{pingDest.to_s} -c 1 -W 5000"
      # now = `ping #{pingDest.to_s} -c 1 -W 5000`
			puts pingCmd

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
				@failCounter = 0
				alertSent = false

			else
				@failCounter += 1
				logObj.debug("thrId: #{@objId}, #{pingDest.to_s} failCounter=#{@failCounter}, exitstatus=#{status.exitstatus}")

				# check if alert needs to be sent
				if alertObj.sendAlerts && (@failCounter >= alertObj.maxPingsBeforeAlert.to_i && !alertSent)
					# send alert, but only one per-occurrence
					alertSent = sendAlert("PING", pingDest.to_s, @failCounter, @objId)
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
    @httpFileHeader = opInput.httpFileHeader.to_s    # static file headers to put at the top of an output file


    # create file to store data to
    pos1 = httpUrl.index(":").to_i
    fileName = httpUrl[0,pos1] + "_" + httpUrl[pos1+3, httpUrl.length - (pos1+3)]


    # start crawling
		currEpoch = 0
    loop do
      startTime = DateTime.now.strftime('%Q').to_s

      begin
        # queryResponse = open(@httpUrl.to_s)
				# puts queryResponse.class

				queryResponse = HTTParty.get(@httpUrl.to_s, {timeout: 5})

				# response.body, response.code, response.message, response.headers.inspect
				# puts "body: #{queryResponse.body}"
				# puts "code: #{queryResponse.code}"
				# puts "message: #{queryResponse.message}"
				# puts "headers: #{queryResponse.headers.class}"


      # try to rescue from any exceptions, but keep trying
			# TODO: for some reason the rescue clauses below throw runtime errors on Mac OS
			rescue Exception => e
				# TODO: do some logging before re-raising the exception
				puts "#{e}"
				logObj.error("thrId: #{@objId}, runHttpQueries() #{e}")
				@failCounter += 1
				logObj.debug("thrId: #{@objId}, #{httpUrl.to_s} failCounter=#{@failCounter}")

				#puts "FAILED, " + "#{failCounter}\t" + "#{alertObj.maxPingsBeforeAlert.to_i}"
				if @alertObj.sendAlerts && (@failCounter >= @alertObj.maxHTTPBeforeAlert.to_i && !@alertSent)
					# send alert, but only one per-occurrence
					@alertSent = sendAlert("HTTP", @httpUrl.to_s, @failCounter, @objId)
				end

				#raise e  # TODO: re-raise exception previously ignored and process properly

			else
				# no exceptions
				@failCounter = 0
			end

			currEpoch = DateTime.now.strftime('%Q').to_s	# time when query finished
			hValues = {}

			# if the query failed, save a whole bunch of -1s to file
			if @failCounter > 0
				duration = -1
				hValues = {length: "-1", code: "-1", message: "-1", headers: "-1"}
			else
      	duration = currEpoch.to_i - startTime.to_i  # time taken to do the HTTP GET, in milliseconds
				hValues = {length: queryResponse.body.length,
					code: queryResponse.code,
					# message: queryResponse.message,
					# headers: queryResponse.headers
				}

				# reset flags and variables
				@alertSent = false
				@failCounter = 0
			end


			# store data in influxDB
			data = {
				values: hValues,
				timestamp: currEpoch,
			}
			influxDBObj.write_point("HTTP_"+httpUrl.to_s, data)


			# show some output in the terminal
			httpOutput = objId.to_s + ", " + httpCounter.to_s + ", " + httpUrl + ", " + duration.to_s + " ms"
			httpOutput += ", code: #{hValues[:code]}\tlength: #{hValues[:length]}"
      puts httpOutput
			logObj.info(httpOutput)

			# puts "\talertSent: #{@alertSent}\tfailCounter: #{@failCounter}"


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

  end

	def sendAlert(op, dest, failCount, id=-1)
		# send email alert using the Alert object passed to the class initialiser
		currEpoch = DateTime.now.strftime('%Q')	# this so that logs and email alert have the same timestamp
		output = @alertObj.sendEmailAlert(op, dest, failCount, currEpoch.to_s, DateTime.strptime(currEpoch,'%Q'))

		if output
			puts "[#{currEpoch},#{objId.to_s}]: #{op} Alert sent, #{dest}"
			@logObj.info("thrId: #{@objId}, #{op} Alert sent, #{dest}")
			return true
		else
			puts "[#{currEpoch},#{objId.to_s}]: #{op} Failed to send email alert, #{dest}"
			@logObj.info("thrId: #{@objId}, #{op} Failed to send email alert, #{dest}")
			return false
		end
	end


  # accessors for instance variables
  attr_accessor :objId, :alertObj, :logObj, :influxDBObj

  attr_accessor :pingDelay, :pingDest, :pingCounter, :pingLimit, :pingFileHeader, :pingDstIsIP

  attr_accessor :httpUrl, :httpDelay, :httpCounter, :httpLimit, :httpFileHeader

	# generic variables
	attr_accessor :failCounter, :alertSent

end
