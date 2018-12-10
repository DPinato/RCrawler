# class used to store input from the config file

class Operation
# TODO: probably a struct would be better than this

  def initialize(opType, dest, interval, reps, httpFileHeader)
    @opType = opType			# operation type, i.e. HTTP, PING, ...
    @dest = dest					# PING/HTTP destination
    @interval = interval	# sleep timer after the operation has completed
    @reps = reps					# number of times the operation will be repeated

    @httpFileHeader = httpFileHeader
  end

  attr_accessor :opType, :dest, :interval, :reps, :httpFileHeader

end
