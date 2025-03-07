dq = daq("ni");
addinput(dq,"Dev2","ai0","Voltage");
addinput(dq,"Dev2","port0/line1","Digital")
addtrigger(dq,"Digital","StartTrigger","External","Dev2/PFI0");
%%
ex = experiment();
ex = loadInstruments(ex,"pulse blaster","pulse_blaster_default");
ex.pulseBlaster.nTotalLoops = 1;%will be overwritten later, used to find time for 1 loop
ex.pulseBlaster.useTotalLoop = true;
ex.pulseBlaster = deleteSequence(ex.pulseBlaster);

ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{},99,'τ without-RF time');%Scanned
ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'AOM','Data'},200,'Reference Data collection');
ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'RF','Signal'},99,'τ with-RF time');%Scanned
ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'AOM','Data','Signal'},200,'Signal Data collection');
ex.pulseBlaster = standardTemplateModifications(ex.pulseBlaster,15e3,10e3,...
    100,0,[],0,0);

ex.pulseBlaster = calculateDuration(ex.pulseBlaster,'user');
ex.pulseBlaster.nTotalLoops = floor(10/ex.pulseBlaster.sequenceDurations.user.totalSeconds);

ex.pulseBlaster = sendToInstrument(ex.pulseBlaster);
%%
triggerTime = seconds(3e-6);
dq.Rate = 2e6;
dq.NumDigitalTriggersPerRun = 20;
dq.DigitalTriggerTimeout = 2;
runSequence(ex.pulseBlaster)
pause(5)
tic
try
% [data, startTime] = read(dq, triggerTime);
catch ME
    stopSequence(ex.pulseBlaster)
    rethrow(ME)
end
stopSequence(ex.pulseBlaster)
toc