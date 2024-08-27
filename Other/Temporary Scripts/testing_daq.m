if ~exist('ex','var')
   ex = experiment;
end

if isempty(ex.pulseBlaster)
   ex.pulseBlaster = pulse_blaster('PB');
   ex.pulseBlaster = connect(ex.pulseBlaster);
end

ex.pulseBlaster.nTotalLoops = 4000;
ex.pulseBlaster.useTotalLoop = true;
ex.pulseBlaster = deleteSequence(ex.pulseBlaster);

% clear pulseInfo 
% pulseInfo.activeChannels = {};
% pulseInfo.duration = 2500;
% pulseInfo.notes = 'Initial buffer';
% ex.pulseBlaster = addPulse(ex.pulseBlaster,pulseInfo);

clear pulseInfo 
pulseInfo.activeChannels = {'AOM','DAQ','I','Q'};
pulseInfo.duration = 1e6;
pulseInfo.notes = 'Reference';
ex.pulseBlaster = addPulse(ex.pulseBlaster,pulseInfo);

% clear pulseInfo 
% pulseInfo.activeChannels = {};
% pulseInfo.duration = 2500;
% pulseInfo.notes = 'Middle buffer signal off';
% ex.pulseBlaster = addPulse(ex.pulseBlaster,pulseInfo);

% clear pulseInfo 
% pulseInfo.activeChannels = {};
% pulseInfo.duration = 2500;
% pulseInfo.notes = 'Middle buffer signal on';
% ex.pulseBlaster = addPulse(ex.pulseBlaster,pulseInfo);

clear pulseInfo 
pulseInfo.activeChannels = {'AOM','DAQ','RF','I','Q'};
pulseInfo.duration = 1e6;
pulseInfo.notes = 'Signal';
ex.pulseBlaster = addPulse(ex.pulseBlaster,pulseInfo);

% clear pulseInfo 
% pulseInfo.activeChannels = {};
% pulseInfo.duration = 2500;
% pulseInfo.notes = 'Final buffer';
% ex.pulseBlaster = addPulse(ex.pulseBlaster,pulseInfo);

%Sends the currently saved pulse sequence to the pulse blaster instrument itself
ex.pulseBlaster = sendToInstrument(ex.pulseBlaster);

%%
n = 0;
while n < 50
runSequence(ex.pulseBlaster)
while pbRunning(ex.pulseBlaster)
    pause(.001)
end
stopSequence(ex.pulseBlaster)
disp(n)
pause(.3)
n = n+1;
end