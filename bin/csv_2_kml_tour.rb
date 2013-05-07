require_relative File.join('..', 'lib', 'csv_2_kml_tour')
require_relative File.join('..', 'lib', 'progress_status')
require 'English'
require 'date'

if __FILE__ == $PROGRAM_NAME
  Csv2KmlTour.new.run
end


