# this class is used to send alerts to registered email addresses and what not


class Alerter

  def initialize(emails, maxPings=-1, maxHTTPs=-1)
    @emailAddresses = emails
    @maxPingsBeforeAlert = maxPings
    @maxHTTPBeforeAlert = maxHTTPs

  end


  def readEmailTemplate(templateLocation)


  end


  def sendEmailAlert()


  end



  attr_accessor :emailAddresses
  attr_accessor :maxPingsBeforeAlert
  attr_accessor :maxHTTPBeforeAlert

end
