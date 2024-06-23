pb = pulse_blaster; %Creates empty pulse blaster object

%Technically not a connection, but it prepares matlab for interacting with
%the pulse blaster in a manner similar to all the other connection
%functions so the name is the same
pb = connect(pb,'pulse_blaster_config');

piDuration = 62;%Example pi duration in ns
pb.nTotalLoops = 200;

%Possible fields for pulseInfo:
%.activeChannels: a cell array of the names of the channels
%.channelsBinary: character array of 1s and 0s representing each channel
%.numericalOutput: conversion of above into decimal form
%.duration: how long the pulse lasts
%.directionType: what the pulse blaster should do at this step (continue,
   %loop, end loop)
%.contextInfo: info pertaining to the directionType. Usually used for
   %number of loops a loop command should go for
%.notes: user's notes describing the pulse

%Of these fields, the duration is always required as is one of the fields
%for indicating channel activity (.activeChannels, .channelBinary, or
%.numericalOutput). directionType defaults to continue and is therefore
%unnecessary unless you want to designate a loop or end loop. contextInfo
%is irrelevant for most pulses (continue doesn't use it and end loop gets
%overwritten in the sendToInstrument function) so it is mainly needed only
%for the loop directionType. notes is completely optional

%Below is an example sequence using a variety of inputs to show what is
%possible

%Creates an RF pulse with the I channel on for a duration of π/2
clear pulseInfo %Used to prevent any holdovers from previous pulses
pulseInfo.activeChannels = {'RF','I'};
pulseInfo.duration = piDuration/2;
pulseInfo.notes = 'Initial π/2';
pb = addPulse(pb,pulseInfo);

%Creates an empty pulse, useful for buffers or the like, of 100 ns
clear pulseInfo
pulseInfo.activeChannels = {};
pulseInfo.duration = 100;
pb = addPulse(pb,pulseInfo);

%Creates a loop (that includes itself) running for 10,000 times of a π
%pulse with Q on
clear pulseInfo
pulseInfo.activeChannels = {'RF','Q'};
pulseInfo.duration = 7000;
pulseInfo.directionType = 'start loop';%loops are inclusive for start and end
pulseInfo.contextInfo = 10000;%nLoops
pulseInfo.notes = 'π starting loop';
pb = addPulse(pb,pulseInfo);

%Turns AOM and data collection on for 1 μs
clear pulseInfo
pulseInfo.activeChannels = {'aom','data'};
pulseInfo.duration = 1000;
pb = addPulse(pb,pulseInfo);

clear pulseInfo
pulseInfo.numericalOutput = 0;
pulseInfo.duration = 50;
pulseInfo.directionType = 'end loop';%loops are inclusive for start and end
pb = addPulse(pb,pulseInfo);

clear pulseInfo
pulseInfo.channelsBinary = '1 0 0 0 0 0';%Spaces are optional
pulseInfo.duration = 5000;
pulseInfo.notes = 'Repolarization with AOM on';
pb = addPulse(pb,pulseInfo);

%%

%Sends the current pulse sequence to the pulse blaster
pb = sendToInstrument(pb);

%Self-explanatory
runSequence(pb)

%While the pulse blaster is still running, wait
n = 0;
while pbRunning(pb)
   pause(1e-3)
   n = n+1;
   if n > 1e4
       fprintf('timeout')
       break       
   end
end

%Stops the sequence just in case something has gone wrong. *Shouldn't* be
%necessary, but is good practice
stopSequence(pb)

data = [123,456];%Fake signal and reference data (would be from DAQ)

%Calculates data per unit time by referencing the data collection duration
%for the sequence sent to the pulse blaster
dataPerNanoSecond = data ./ pb.sentSequenceDataDuration;
dataPerSecond = dataPerNanoSecond ./ 1e-9;

%What fraction of the sequence's time is spent collecting data
dataCollectionRatio = pb.sentSequenceDataDuration / pb.sentSequenceDuration;








