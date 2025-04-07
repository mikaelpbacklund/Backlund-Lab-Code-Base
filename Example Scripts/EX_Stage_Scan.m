%Scans stage across 1 dimension

clear p

%Reminders on functions to move stage or get location
%stageLocations = ex.PIstage.axisSum;
%ex.PIstage = absoluteMove(ex.PIstage,'z',7500);
%ex.PIstage = relativeMove(ex.PIstage,'z',-50);

%% User Inputs
p.scanBounds = {[6300 6800]};
p.scanAxes = {'z'};
p.scanStepSize = {2};
p.collectionType = 'counter';%analog or counter

%General
p.contrastVSReference = 'ref';%'ref' or 'con'. If con, applies ODMR sequence but shows ref and con; if ref, uses fast sequence and only shows ref
p.sequenceTimePerDataPoint = .1;%Before factoring in forced delay and other pauses
p.scanNotes = 'Stage scan'; %Notes describing scan (will appear in titles for plots)
p.RFAmplitude = 10;%Only applicable if contrast enabled
p.RFFrequency = 2.87;%Only applicable if contrast enabled
p.nIterations = 10; %Number of iterations of scan to perform
p.timeoutDuration = 10; %How long before auto-continue occurs
p.forcedDelayTime = .125; %Time to force pause before (1/2) and after (full) collecting data
p.nDataPointDeviationTolerance = .0001;%How precies measurement is. Lower number means more exacting values, could lead to repeated failures
p.baselineSubtraction = 0;%Amount to subtract from both reference and signal collected
p.perSecond = true;
p.intermissionBufferDuration = 1000;

%Config file names
p.pulseBlasterConfig = 'pulse_blaster_DEER';
p.SRSRFConfig = 'SRS_RF';%Only applicable if contrast enabled
p.DAQConfig = 'daq_6361';
p.stageConfig = 'PI_stage';

%Plotting
p.plotAverageReference = true;
p.plotCurrentReference = true;
p.plotAverageContrast = true;%Only applicable if contrast enabled
p.plotCurrentContrast = false;%Only applicable if contrast enabled
p.plotAverageSNR = false;%Only applicable if contrast enabled
p.plotCurrentSNR = false;%Only applicable if contrast enabled
p.invertSignalForSNR = false;%Only applicable if contrast enabled
p.plotCurrentDataPoints=false;
p.plotAverageDataPoints=false;
p.plotPulseSequence = false;

%% Backend

if ~exist('ex','var')
   ex = experiment;
end

if isempty(ex.pulseBlaster)
    fprintf('Connecting to pulse blaster...\n')
   ex.pulseBlaster = pulse_blaster('pulse_blaster_DEER');
   ex.pulseBlaster = connect(ex.pulseBlaster);
   fprintf('Pulse blaster connected\n')
end
if isempty(ex.SRS_RF) && strcmp(contrastVSReference,'con')
    fprintf('Connecting to SRS...\n')
   ex.SRS_RF = RF_generator('SRS_RF');
   ex.SRS_RF = connect(ex.SRS_RF);
   fprintf('SRS connected\n')
end
if isempty(ex.DAQ)
    fprintf('Connecting to DAQ...\n')
   ex.DAQ = DAQ_controller('daq_6361');
   ex.DAQ = connect(ex.DAQ);
   fprintf('DAQ connected\n')
end
if isempty(ex.PIstage)
    fprintf('Connecting to PI stage...\n')
   ex.PIstage = stage('PI_stage');
   ex.PIstage = connect(ex.PIstage);
   fprintf('PI stage connected\n')
end

ex.DAQ.takeData = false;
ex.DAQ.activeDataChannel = dataType;

ex.pulseBlaster.nTotalLoops = 1;%will be overwritten later, used to find time for 1 loop
ex.pulseBlaster.useTotalLoop = true;
ex.pulseBlaster = deleteSequence(ex.pulseBlaster);

if strcmpi(contrastVSReference,'con')
   if isempty(ex.SRS_RF) %#ok<*UNRCH>
      ex.SRS_RF = RF_generator('SRS_RF');
      ex.SRS_RF = connect(ex.SRS_RF);
   end

   ex.SRS_RF.enabled = 'on';
   ex.SRS_RF.modulationEnabled = 'off';
   ex.SRS_RF.amplitude = RFamplitude;
   ex.SRS_RF.frequency = RFfrequency;

   ex.DAQ.differentiateSignal = true;
   ex.DAQ.continuousCollection = true;

   ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{},2500,'Initial buffer');
   ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'AOM','DAQ'},1e6,'Reference');
   ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'AOM','DAQ'},1e6,'Reference');
   ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{},2500,'Middle buffer signal off');
   ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'Signal'},2500,'Middle buffer signal on');
   ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'AOM','DAQ','RF','Signal'},1e6,'Signal');
   ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'Signal'},2500,'Final buffer');
else
   ex.DAQ.differentiateSignal = false;
   ex.DAQ.continuousCollection = false;

   ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'AOM'},500,'Initial buffer');
   ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'AOM','DAQ'},1e6,'Taking data');
end

ex.pulseBlaster = calculateDuration(ex.pulseBlaster,'user');

%Changes number of loops to match desired time for each data point
ex.pulseBlaster.nTotalLoops = floor(sequenceTimePerDataPoint/ex.pulseBlaster.sequenceDurations.user.totalSeconds);

ex.pulseBlaster = sendToInstrument(ex.pulseBlaster);

ex.scan = [];

%Adds each scan
for ii = 1:numel(scanBounds)
   scan.bounds = scanBounds{ii};
   scan.stepSize = scanStepSize{ii};
   scan.parameter = scanAxes{ii};
   scan.identifier = 'stage';
   scan.notes = scanNotes;

   ex = addScans(ex,scan);
end

%Adds time (in seconds) after pulse blaster has stopped running before continuing to execute code
ex.forcedCollectionPauseTime = forcedDelayTime;

ex.maxFailedCollections = 3;

ex.nPointsTolerance = nDataPointDeviationTolerance;

%Sends information to command window
% scanStartInfo(ex.scan.nSteps,ex.pulseBlaster.sequenceDurations.sent.totalSeconds + ex.forcedCollectionPauseTime*1.5,nIterations,.28)

cont = checkContinue(timeoutDuration*2);
if ~cont
    return
end

%% Running Scan
try
    if strcmp(contrastVSReference,'con')
        ex = resetAllData(ex,[0,0]);
    else
        ex = resetAllData(ex,0);
    end

for ii = 1:nIterations
   
   ex = resetScan(ex);
   
   while ~all(cell2mat(ex.odometer) == [ex.scan.nSteps]) %While odometer does not match max number of steps

      ex = takeNextDataPoint(ex,'pulse sequence');

      odoCell = num2cell(ex.odometer);
      currentData = ex.data.values{odoCell{:},ex.data.iteration(odoCell{:})};
      if ii == 1
          averageData = currentData;
      else
        averageData = mean(createDataMatrixWithIterations(ex,ex.odometer),numel(ex.scan)+1);
      end      

      %Create plot for contrast if set to that
      if strcmpi(contrastVSReference,'con')
         avgContrast = (averageData(1)-averageData(2))/averageData(1);
         ex = plotData(ex,avgContrast,'Average Contrast');
         curContrast = (currentData(1)-currentData(2))/currentData(1);
         ex = plotData(ex,curContrast,'Current Iteration Contrast');
      end

      ex = plotData(ex,averageData(1),'Average Reference');
      ex = plotData(ex,currentData(1),'Current Iteration Reference');
   end

   if ii ~= nIterations
       fprintf('Finished iteration %d\n',ii)

       cont = checkContinue(timeoutDuration);
       if ~cont
           break
       end
   end
end

fprintf('Scan complete\n')

catch ME   
    stop(ex.DAQ.handshake)
    rethrow(ME)
end

stop(ex.DAQ.handshake)