# class used to store input from the config file

class Operation
# TODO: probably a struct would be better here

  def initialize(opType, dest, interval, reps, outputDir, httpFileHeader)
    @opType = opType
    @dest = dest
    @interval = interval
    @reps = reps
    @outputDir = outputDir
    @httpFileHeader = httpFileHeader
  end

  attr_accessor :opType, :dest, :interval, :reps, :outputDir, :httpFileHeader

end
