# class used to store input from the config file

class Operation
# TODO: probably a struct would be better here

  def initialize(opType, dest, interval, reps, outputDir, httpFileHeader, pingFileHeader)
    @opType = opType
    @dest = dest
    @interval = interval
    @reps = reps
    @outputDir = outputDir
    @httpFileHeader = httpFileHeader
    @pingFileHeader = pingFileHeader
  end

  attr_accessor :opType
  attr_accessor :dest
  attr_accessor :interval
  attr_accessor :reps
  attr_accessor :outputDir
  attr_accessor :httpFileHeader
  attr_accessor :pingFileHeader
end
