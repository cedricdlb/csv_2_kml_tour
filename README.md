csv_2_kml_tour
==============

Takes as input a CSV file of timestamps and floats (Output from GridLAB-D group_recorder), a nominal value for the floats, etc. and writes a KML gx:Tour as a heatmap of values as % of nominal, changing over time.  The use case is a CSV of power line voltages, and given a kml file of the power lines, shows the nominal, over- and under-voltage conditions. The CSV file consists of some header lines starting with the hash (#) character, the last of which gives the column names, followed by csv data rows as date_time_stamp,val_1,...val_N.