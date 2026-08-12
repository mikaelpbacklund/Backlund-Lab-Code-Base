configName = 'daq_testing';

daqtest = DAQ_controller_test(configName);
daqtest = connect(daqtest);
daqtest.activeDataChannel = 'analog';
daqtest.pollInterval = 1;


%%
startDAQ(daqtest)

%%
%samplesToReset based on length per loop of sequence and DAQ rate
secondsPerLoop = pulseController.sequenceDurations.user.totalSeconds ./ pulseController.nTotalLoops;
samplesPerLoop = daqtest.handshake.Rate .*  secondsPerLoop;
if pulseController.sequenceDurations.user.dataFraction > .1
    daqtest.samplesToReset = samplesPerLoop.*2;
else
    %Low amount of data collection per loop
    daqtest.samplesToReset = samplesPerLoop.*10;
end
%%
startDAQ(daqtest)
pause(1)
jj = 300;
clear n r s c

for ii = 1:jj
    runSequence(pulseController);
    while pbRunning(pulseController)
        pause(.005)
    end
end
pause(1)
stopDAQ(daqtest);

dn = pulseController.sequenceDurations.user.dataNanoseconds;
expectedSamples = (dn*1E-9)*daqtest.handshake.Rate;
acquiredSamples = daqtest.referencePoints+daqtest.signalPoints;

%%
for blockNumber = 1:numel(allBlocks)
    if ismember(allBlocks(blockNumber),emptyBlockStarts)
        %Begins empty block
        %Finalize point, then move on
        % finalizePoint(obj)
    else
        %Begins data block
        %Add data from the start of the data block to the start
        %of the next empty block, or the end of the run
        dataBlockStart = dataBlockStarts(dataBlockStarts == allBlocks(blockNumber));
        if blockNumber ~= numel(allBlocks)
            dataBlockEnd = allBlocks(blockNumber+1);
        else
            dataBlockEnd = size(raw,1);
        end

        test = raw(dataBlockStart:dataBlockEnd,:);
        % processBlock(obj,raw(dataBlockStart:dataBlockEnd,:));
    end
end
