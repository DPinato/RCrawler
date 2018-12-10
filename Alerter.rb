# this class is used to send alerts to registered email addresses and what not

class Alerter

  def initialize(emails, maxPings=-1, maxHTTPs=-1, send=true)
    @emailAddresses, @maxPingsBeforeAlert, @maxHTTPBeforeAlert, @sendAlerts = emails, maxPings, maxHTTPs, send

  end


  def readEmailTemplate(templateLocation)
		# load the alert template from the file in the specified location
		@alertTemplatelocation = templateLocation
		puts "Reading template..." + @alertTemplatelocation.to_s
		@alertTemplate = File.read(@alertTemplatelocation.to_s)

  end


  def sendEmailAlert(op, dest, fails, sEpoch, sDate)
		# first finish generating the email from the template
		@emailMessage = @alertTemplate.dup	# otherwise the copy would be by reference
		@emailSubject = "ALERT(#{op.to_s}): #{dest.to_s} - #{sDate.to_s}"
		emailMessage.sub!("<op>", op.to_s)
		emailMessage.sub!("<dest>", dest.to_s)
		emailMessage.sub!("<fails>", fails.to_s)
		emailMessage.sub!("<sEpoch>", sEpoch.to_s)
		emailMessage.sub!("<sDate>", sDate.to_s)
		#puts "\t" + "#{emailMessage}"

		# use either of the commands below to send the email
		# echo "<emailMessage>" | mail -s "<emailSubject>" emailAddress
		# mail -s "<subject>" <email_address> < "<file>"

		# TODO: the mail command fails silently, replace with something else?
		cmdTest1 = "echo \"#{emailMessage.to_s}\" | mail -s \"#{emailSubject.to_s}\" #{emailAddresses.to_s}"
		#puts cmdTest1
		output = `#{cmdTest1}`

		#cmdTest2 = "mail -s \"#{emailSubject.to_s}\" #{emailAddresses.to_s} < \"#{emailMessage.to_s}\""
		#puts cmdTest2
		#output = `#{cmdTest2}`

		return true

  end



  attr_accessor :emailAddresses, :alertTemplateLocation, :maxPingsBeforeAlert, :maxHTTPBeforeAlert, :sendAlerts

	attr_accessor :alertTemplateLocation, :emailMessage, :emailSubject

end
