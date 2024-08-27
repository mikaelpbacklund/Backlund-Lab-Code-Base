function [varargout] = Rabi_template(h,p)
    %Creates Spin Echo sequence based on given parameters
    %h is pulse blaster object, p is parameters structure

    parameterFieldNames = ["RFResonanceFrequency","tauStart","tauEnd","tauNSteps","tauStepSize",...
      "timePerDataPoint","collectionDuration","collectionBufferDuration","repolarizationDuration",...
      "intermissionBufferDuration","RFReduction","AOM_DAQCompensation"];

      %If no pulse blaster object is given, returns default parameter structure and list of field names   
    if isempty(h)       
      %Creates default parameter structure
      parameterStructure.RFResonanceFrequency = [];
      parameterStructure.tauStart = [];
      parameterStructure.tauEnd = [];
      parameterStructure.tauNSteps = [];
      parameterStructure.tauStepSize = [];
      parameterStructure.timePerDataPoint = 1;
      parameterStructure.collectionDuration = 1000;
      parameterStructure.collectionBufferDuration = 1000;
      parameterStructure.repolarizationDuration = 7000;
      parameterStructure.intermissionBufferDuration = 2500;
      parameterStructure.RFReduction = 0;
      parameterStructure.AOM_DAQCompensation = 0;

      varargout{1} = parameterStructure;%returns default parameter structure as first output

      varargout{2} = parameterFieldNames;%returns list of field names as second output
      return
    end

    if ~isstruct(p)
      error('Parameter input must be a structure')
    end

    %Check if required parameters fields are present
    mustContainField(p,parameterFieldNames);

    if isempty(p.RFResonanceFrequency) || isempty(p.tauStart) || isempty(p.tauEnd) || (isempty(p.tauNSteps) && isempty(p.tauStepSize))
      error('Parameter input must contain RFResonanceFrequency, tauStart, tauEnd and (tauNSteps or tauStepSize)')
    end       

    %Calculates number of steps if only step size is given
    if isempty(p.tauNSteps)
      p.tauNSteps = ceil(abs((p.tauEnd-p.tauStart)/p.tauStepSize));
    end

    %% Sequence Creation

    %Deletes prior sequence
    h = deleteSequence(h);
    h.nTotalLoops = 1;%Will be overwritten later, used to find time for 1 loop
    h.useTotalLoop = true;

    %First pulse is variable RF duration, second is data collection
    %Second input is active channels, third is duration, fourth is notes
    h = condensedAddPulse(h,{},99,'τ without-RF time');%Scanned
    h = condensedAddPulse(h,{},p.collectionDuration,'Data collection');

    h = condensedAddPulse(h,{'RF'},99,'τ with-RF time');%Scanned
    h = condensedAddPulse(h,{},p.collectionDuration,'Data collection');
    
    %% Sequence Additions/Corrections
    %The following addBuffer functions are done for more or less every template. They add (in order): 
    % a blank buffer between signal and referenece to separate the two fully, a
    %repolarization pulse after data collection, a data collection buffer after the last RF pulse but before the laser or
    %DAQ is turned on to ensure all RF pulses have resolved before data is collected, and an AOM/DAQ compensation pulse
    %which accounts for the discrepancy between time delay between when each instrument turns on after pulse blaster sends a
    %pulse (caused by differences in cable length and other minor electrical discrepancies). They are added in an order such
    %that the final result is in the desired configuration
    
    h = addBuffer(h,findPulses(h,'activeChannels',{'Data'},'contains'),p.intermissionBufferDuration,{'Signal'},'Intermission between halves','after');
    
    h = addBuffer(h,findPulses(h,'activeChannels',{'Data'},'contains'),p.repolarizationDuration,{'AOM','Signal'},'Repolarization','after');
    
    h = addBuffer(h,findPulses(h,'activeChannels',{'Data'},'contains'),preCollectionBufferDuration,{'Signal'},'Data collection buffer','before');
    
    %Negative number indicates DAQ pulse must be sent first
    if p.AOM_DAQCompensation > 0
       %Adds pulse with AOM on to account for lag between AOM and DAQ
       h = addBuffer(h,findPulses(h,'activeChannels',{'Data'},'contains'),p.AOM_DAQCompensation,{'AOM','Signal'},'DAQ delay compensation','before');
       
       %Shortens the repolarization time in accordance with the added time above
       newRepolarization = repolarizationDuration - p.AOM_DAQCompensation;
       repolarizationAddresses = findPulses(h,'notes','Repolarization','contains');
       h = modifyPulse(h,repolarizationAddresses,'duration',newRepolarization);
    else
       %Adds pulse with DAQ on to account for lag between DAQ and AOM
       h = addBuffer(h,findPulses(h,'activeChannels',{'Data'},'contains'),abs(p.AOM_DAQCompensation),{'Signal'},'AOM/DAQ delay compensation','before');
       
       %Shortens the data collection time in accordance with the added time above
       newDataDuration = collectionDuration - abs(p.AOM_DAQCompensation);
       dataAddresses = findPulses(h,'notes','data collection','contains');
       h = modifyPulse(h,dataAddresses,'duration',newDataDuration);
    end

    %Changes number of loops to match desired time
    h.nTotalLoops = p.timePerDataPoint/h.sequenceDurations.user.totalSeconds;

    %Sends the completed sequence to the pulse blaster
    h = sendToInstrument(h);
    
    %% Scan Calculations      

    %Finds pulses designated as τ which will be scanned
    scanInfo.address = findPulses(h,'notes','τ','contains');
    
    %Info regarding the scan
    for ii = 1:numel(scanInfo.address)
       scanInfo.bounds{ii} = [p.tauStart p.tauEnd];
    end
    scanInfo.nSteps = p.tauNSteps;
    scanInfo.parameter = 'duration';
    scanInfo.identifier = 'Pulse Blaster';
    scanInfo.notes = sprintf('Rabi (RF: %.3f GHz)',p.RFResonanceFrequency);
    scanInfo.RFFrequency = p.RFResonanceFrequency;

    %% Outputs
    varargout{1} = h;%returns pulse blaster object
    varargout{2} = scanInfo;%returns scan info
    
    end