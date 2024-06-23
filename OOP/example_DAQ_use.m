%Creates object
nidaq = NI_DAQ;

%Connects to instrument using NI_DAQ_config config file. Config file
%contains information about channel designations.
nidaq = connect(nidaq,'NI_DAQ_config');

%% For Stage Scans

%Simply get counts rather than distinguish signal and reference
nidaq = setSignalDifferentiation(nidaq,'off');

%Do not use continuous collection
nidaq.continousCollection = false;

%Makes counter the data channel. Can also be input as a number or a port
%name if desired
nidaq = setDataChannel(nidaq,'counter');

%Reset DAQ in preparation for measurement
nidaq = resetDAQ(nidaq);

%//Below is commented out code for running the pulse blaster to generate data
%for the DAQ
%runSequence(pulseBlaster)

% while pbRunning(pulseBlaster)
%    pause(.001)
% end

% stopSequence(pulseBlaster)
%//End pulse blaster commented code

%Get total number of counts out
countsOut = readData(nidaq);

%% For Everything Else

%For stage optimizations, continuousCollection is on but
%differentiateSignalReference is off. This is faster than stopping the DAQ
%then restarting it as would be needed if continuousCollection is off. It
%was found phenomonologically that turning it on and off is a time saver
%for longer stage scans but not for short optimizations

%For anything besides a straight counts measurement
nidaq = differentiateSignalReference(nidaq,'on');

%Reset DAQ in preparation for measurement
nidaq = resetDAQ(nidaq);

%//Below is commented out code for running the pulse blaster to generate data
%for the DAQ
%runSequence(pulseBlaster)

% while pbRunning(pulseBlaster)
%    pause(.001)
% end

% stopSequence(pulseBlaster)
%//End pulse blaster commented code

[reference,signal] = readData(nidaq);

%Example of what can be done with data
contrast = (reference-signal)/reference;

%Turn off continuous data collection of the daq
nidaq = setContinuousCollection(nidaq,'off');
nidaq = resetDAQ(nidaq);











