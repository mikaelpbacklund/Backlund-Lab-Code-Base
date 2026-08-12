configName = 'pb_swabian';

%%
pulseController = pulse_blaster(configName);
pulseController = connect(pulseController);

%%
timePerPoint = .01;%s
pulseController.nTotalLoops = 1;%will be overwritten later, used to find time for 1 loop
pulseController.useTotalLoop = true;
pulseController = deleteSequence(pulseController);

%Condensed version below puts this on one line
% pulseController = condensedAddPulse(pulseController,{},2500,'Initial buffer signal off');
% pulseController = condensedAddPulse(pulseController,{'AOM','DAQ'},1e6,'Reference');
% pulseController = condensedAddPulse(pulseController,{},2500,'Middle intermission buffer signal off');
% pulseController = condensedAddPulse(pulseController,{'Signal'},2500,'Middle buffer signal on');
% pulseController = condensedAddPulse(pulseController,{'AOM','DAQ','RF','Signal'},1e6,'Signal');
% pulseController = condensedAddPulse(pulseController,{'Signal'},2500,'Final buffer');
pulseController = condensedAddPulse(pulseController,{},100,'Initial buffer signal off');
pulseController = condensedAddPulse(pulseController,{'AOM','DAQ'},1e4,'Reference');
pulseController = condensedAddPulse(pulseController,{},100,'Middle intermission buffer signal off');
pulseController = condensedAddPulse(pulseController,{'Signal'},100,'Middle buffer signal on');
pulseController = condensedAddPulse(pulseController,{'AOM','DAQ','RF','Signal'},1e4,'Signal');
pulseController = condensedAddPulse(pulseController,{'Signal'},100,'Final buffer');

pulseController = calculateDuration(pulseController,'user');
pulseController.nTotalLoops = floor(timePerPoint/pulseController.sequenceDurations.user.totalSeconds);

%Sends the currently saved pulse sequence to the pulse blaster instrument itself
pulseController = sendToInstrument(pulseController);


%%
% runSequence(pulseController)
%%
setConstantOutput(pulseController,[]);