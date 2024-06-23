%I have intentionally removed all comments from this script to force myself
%to make easily readable code. This runs an ODMR with stage optimization

warning('off','MATLAB:subscripting:noSubscriptsSpecified');

if ~exist('ex','var')
   ex = experiment_beta;
end

if isempty(ex.pulseBlaster)
   ex.pulseBlaster = pulse_blaster;
   ex.pulseBlaster = connect(ex.pulseBlaster,'pulse_blaster_config');
end

if isempty(ex.RF)
   ex.RF = RF_generator;
   ex.RF = connect(ex.RF,'RF_generator_config');
end

if isempty(ex.DAQ)
   ex.DAQ = DAQ_controller;
   ex.DAQ = connect(ex.DAQ,'NI_DAQ_config');
end

if isempty(ex.PIstage)
   ex.PIstage = stage;
   ex.PIstage = connect(ex.PIstage,'PI_stage_config');
end

ex.RF.enabled = 'on';
ex.RF.modulationEnabled = 'off';
ex.RF.amplitude = 10;

ex.DAQ.takeData = false;
ex.DAQ.differentiateSignal = 'on';
ex.DAQ.activeDataChannel = 'counter';

ex.pulseBlaster.nTotalLoops = 300;
ex.pulseBlaster.useTotalLoop = true;
ex.pulseBlaster.userSequence = [];

clear pulseInfo 
pulseInfo.activeChannels = {};
pulseInfo.duration = 2500;
pulseInfo.notes = 'Initial buffer';
ex.pulseBlaster = addPulse(ex.pulseBlaster,pulseInfo);

clear pulseInfo 
pulseInfo.activeChannels = {'AOM','DAQ'};
pulseInfo.duration = 1e6;
pulseInfo.notes = 'Reference';
ex.pulseBlaster = addPulse(ex.pulseBlaster,pulseInfo);

clear pulseInfo 
pulseInfo.activeChannels = {};
pulseInfo.duration = 2500;
pulseInfo.notes = 'Middle buffer signal off';
ex.pulseBlaster = addPulse(ex.pulseBlaster,pulseInfo);

clear pulseInfo 
pulseInfo.activeChannels = {'Signal'};
pulseInfo.duration = 2500;
pulseInfo.notes = 'Middle buffer signal on';
ex.pulseBlaster = addPulse(ex.pulseBlaster,pulseInfo);

clear pulseInfo 
pulseInfo.activeChannels = {'AOM','DAQ','RF','Signal'};
pulseInfo.duration = 1e6;
pulseInfo.notes = 'Signal';
ex.pulseBlaster = addPulse(ex.pulseBlaster,pulseInfo);

clear pulseInfo 
pulseInfo.activeChannels = {'Signal'};
pulseInfo.duration = 2500;
pulseInfo.notes = 'Final buffer';
ex.pulseBlaster = addPulse(ex.pulseBlaster,pulseInfo);

ex.pulseBlaster = sendToInstrument(ex.pulseBlaster);

optimizationSequence.consecutive = true;
optimizationSequence.axes = {'Z'};
optimizationSequence.steps = {-.5:.05:.5};

ex.scan = [];

scan.bounds = [2.5 3];
scan.stepSize = .005;
scan.parameter = 'frequency';
scan.instrument = 'SRS RF';
scan.notes = 'ODMR';

ex = addScans(ex,scan);

ex.forcedCollectionPauseTime = .05;

ex = validateExperimentalConfiguration(ex,'pulse sequence');

fprintf('Number of steps in scan: %d\n',ex.scan.nSteps)

nIterations = 1;

ex = resetAllData(ex,[0 0]);

for ii = 1:nIterations
   
   ex = resetScan(ex);
   
   ex = stageOptimization(ex,'max value','pulse sequence',optimizationSequence,'off');
   lastOptTime = datetime;
   
   while ~all(ex.odometer == [ex.scan.nSteps])
      
      if datetime-lastOptTime > duration(0,.5,0)
         fprintf('beginning optimization\n')
         optTime = datetime;
         ex = stageOptimization(ex,'max value','pulse sequence',optimizationSequence,'off');
         fprintf('end of optimization. Elapsed time:\n')
         disp(datetime - optTime)
         lastOptTime = datetime;
      end

      ex = takeNextDataPoint(ex,'pulse sequence');      

      plotTypes = {'average','new','old'};
      for plotName = plotTypes
         c = findContrast(ex,plotName{1});
         ex = plotData(ex,c,plotName{1});
      end
      refData = cell2mat(cellfun(@(x)x(1),ex.data.current,'UniformOutput',false));
      ex = plotData(ex,refData,'reference');      
   end

   if ii ~= nIterations
       continueIterations = input('Continue? true or false\n');
       if ~continueIterations
           break
       end
   end
end

stop(ex.DAQ.handshake)












