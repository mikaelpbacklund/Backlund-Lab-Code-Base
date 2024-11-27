function h = standardTemplateModifications(h,intermission,repolarization,collectionBuffer,AOM_DAQCompensation,varargin)
%Runs a standard suite of modifications to the pulse sequence
%Used primarily in templates
%Optional argument is for IQ buffers and should be in the form of a 1x2 double i.e. [15 30] for [before after]

%The following addBuffer functions are done for more or less every template. They add (in order):
% a blank buffer between signal and referenece to separate the two fully, a
%repolarization pulse after data collection, a data collection buffer after the last RF pulse but before the laser or
%DAQ is turned on to ensure all RF pulses have resolved before data is collected, and an AOM/DAQ compensation pulse
%which accounts for the discrepancy between time delay between when each instrument turns on after pulse blaster sends a
%pulse (caused by differences in cable length and other minor electrical discrepancies). They are added in an order such
%that the final result is in the desired configuration


assignin("base","userSequence",h.userSequence)
if nargin > 5
    iqBuffers = varargin{1};
   foundAddress = findPulses(h,'activeChannels',{'RF'},'contains');
   h = addBuffer(h,foundAddress,iqBuffers,{'I','Q','Signal'},[],'I/Q buffer');
   for currentAddress = findPulses(h,'activeChannels',{'RF'},'contains')
      %If there was a before buffer, the RF location is not 2nd in sequence, the pulse before has tau in the name, and
      %that pulse has a duration greater than the buffer duration
      %Subtract duration of buffer from the previous pulse
      subtractBoolean = iqBuffers(1) ~= 0 && currentAddress > 2 &&...
         (contains(h.userSequence(currentAddress-2).notes,'τ') || contains(lower(h.userSequence(currentAddress-2).notes),'tau'));
      if subtractBoolean
         previousDuration = h.userSequence(currentAddress-2).duration;
         if iqBuffers(1) >= previousDuration
            error('I/Q buffer cannot be longer than tau pulse')
         end
         h = modifyPulse(h,currentAddress-2,'duration',previousDuration - iqBuffers(1));
      end

      subtractBoolean = iqBuffers(2) ~= 0 && currentAddress < numel(h.userSequence) - 2 &&...
         (contains(h.userSequence(currentAddress+2).notes,'τ') || contains(lower(h.userSequence(currentAddress+2).notes),'tau'));
      if subtractBoolean
         previousDuration = h.userSequence(currentAddress+2).duration;
         if iqBuffers(2) >= previousDuration
            error('I/Q buffer cannot be longer than tau pulse')
         end
         h = modifyPulse(h,currentAddress+2,'duration',previousDuration - iqBuffers(2));
      end
   end
end

h = addBuffer(h,findPulses(h,'activeChannels',{'Data'},'contains'),intermission,{'Signal'},'after','Intermission between halves');

h = addBuffer(h,findPulses(h,'activeChannels',{'Data'},'contains'),repolarization,{'AOM','Signal'},'after','Repolarization');

h = addBuffer(h,findPulses(h,'activeChannels',{'Data'},'contains'),collectionBuffer,{'Signal'},'before','Data collection buffer');

foundAddress = findPulses(h,'activeChannels',{'Data'},'contains');
compDuration = abs(AOM_DAQCompensation);


%Negative number indicates DAQ pulse must be sent first
if AOM_DAQCompensation > 0
    %Adds pulse with AOM on to account for lag between AOM and DAQ
    h = addBuffer(h,foundAddress,compDuration,{'AOM','Signal'},'before','AOM/DAQ delay compensation');
    
    n = 0;
    %Reduces repolarization duration based on compensation duration
    for ii = 1:numel(foundAddress)
       n = n+1;%Number of additional pulses added
      h = modifyPulse(h,foundAddress(ii)+n+1,'duration',h.userSequence(foundAddress(ii)+n+1).duration - compDuration);
    end
else
    % Adds pulse with DAQ on to account for lag between DAQ and AOM
    h = addBuffer(h,foundAddress,compDuration,{'DAQ','Signal'},'before','AOM/DAQ delay compensation');

    n = 0;
    %Reduces data duration based on compensation duration
    for ii = 1:numel(foundAddress)
       n = n+1;%Number of additional pulses added
      h = modifyPulse(h,foundAddress(ii)+n,'duration',h.userSequence(foundAddress(ii)+n).duration - compDuration);
    end
end

assignin("base","userSequencePost",h.userSequence)

end