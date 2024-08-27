%Runs a simple Rabi sequence with no τ compensation or stage optimization

%% User Inputs
scanBounds = [10 250];%ns
scanStepSize = 4; 
scanNotes = 'Rabi'; %Notes describing scan (will appear in titles for plots)
nIterations = 5;
RFFrequency = 2.26;
sequenceTimePerDataPoint = 3;%Before factoring in forced delay and other pauses
timeoutDuration = 10;
forcedDelayTime = .125;
%Offset for AOM pulses relative to the DAQ in particular
%Positive for AOM pulse needs to be on first, negative for DAQ on first
aomCompensation = 400; 
RFReduction = 0;

%Lesser used settings
RFAmplitude = 10;
dataType = 'analog';
scanNSteps = [];%Will override step size if set

%% Loading Instruments
%See ODMR example script for instrument loading information
warning('off','MATLAB:subscripting:noSubscriptsSpecified');

if ~exist('ex','var'),  ex = experiment; end

if isempty(ex.pulseBlaster)
   ex.pulseBlaster = pulse_blaster('PB');
   ex.pulseBlaster = connect(ex.pulseBlaster);
end
if isempty(ex.SRS_RF)
   ex.SRS_RF = RF_generator('SRS_RF');
   ex.SRS_RF = connect(ex.SRS_RF);
end
if isempty(ex.DAQ)
   ex.DAQ = DAQ_controller('NI_DAQ');
   ex.DAQ = connect(ex.DAQ);
end

%Sends RF settings
ex.SRS_RF.enabled = 'on';
ex.SRS_RF.modulationEnabled = 'off';
ex.SRS_RF.amplitude = RFAmplitude;
ex.SRS_RF.frequency = RFFrequency;

%Sends DAQ settings
ex.DAQ.takeData = false;
ex.DAQ.differentiateSignal = 'on';
ex.DAQ.activeDataChannel = dataType;

%% Use template to create sequence and scan

%Load empty parameter structure from template
[parameters,~] = Rabi_template([],[]);

%Set parameters
%Leaves intermissionBufferDuration, collectionDuration, repolarizationDuration, and collectionBufferDuration as default
parameters.RFResonanceFrequency = RFFrequency;
parameters.tauStart = scanBounds(1);
parameters.tauEnd = scanBounds(2);
parameters.timePerDataPoint = sequenceTimePerDataPoint;
parameters.AOM_DAQCompensation = aomCompensation;
if ~isempty(scanNSteps) %Use number of steps if set otherwise use step size
   parameters.tauNSteps = scanNSteps;
else
   parameters.tauStepSize = scanStepSize;
end
parameters.RFReduction = RFReduction;

%Sends parameters to template
%Creates and sends pulse sequence to pulse blaster
%Gets scan information 
[ex.pulseBlaster,scanInfo] = Rabi_template(ex.pulseBlaster,parameters);

%Adds scan to experiment based on template output
ex.addScans(ex,scanInfo);

%Adds time (in seconds) after pulse blaster has stopped running before continuing to execute code
ex.forcedCollectionPauseTime = forcedDelayTime;

%Checks if the current configuration is valid. This will give an error if not
ex = validateExperimentalConfiguration(ex,'pulse sequence');

%Sends information to command window
scanStartInfo(ex.scan.nSteps,ex.pulseBlaster.sequenceDurations.sent.totalSeconds + ex.forcedCollectionPauseTime*1.5,nIterations,.28)

cont = checkContinue(timeoutDuration*2);
if ~cont
    return
end

%% Run scan, and collect and display data

%Prepares experiment to run from scratch
%[0,0] is the value that all initial values for the data will take
%Two values are used because we are storing ref and sig
ex = resetAllData(ex,[0 0]);

for ii = 1:nIterations
   
   %Prepares scan for a fresh start while keeping data from previous
   %iterations
   [ex,instr] = resetScan(ex,instr);
   
   %While the odometer is not at its max value
   while ~all(ex.odometer == [ex.scan.nSteps])

      [ex,instr] = takeNextDataPoint(ex,instr,'pulse sequence');      

      %Plot the average and new contrast for each data point
      plotTypes = {'average','new'};%'old' also viable
      for plotName = plotTypes
         c = findContrast(ex,[],plotName{1});
         ex = plotData(ex,c,plotName{1});
      end      
   end

   if ii ~= nIterations
      cont = checkContinue(timeoutDuration);
      if ~cont
          break
      end
  end
   
end

%Stops continuous collection from DAQ
stop(instr{2}.handshake)

fprintf('Scan complete\n')








