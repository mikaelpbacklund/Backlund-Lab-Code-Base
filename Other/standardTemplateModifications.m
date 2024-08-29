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

if nargin > 5
    h = addBuffer(h,findPulses(h,'activeChannels',{'RF'},'contains'),varargin{1},{'I','Q','Signal'},'I/Q buffer');
end
   
   h = addBuffer(h,findPulses(h,'activeChannels',{'Data'},'contains'),intermission,{'Signal'},'Intermission between halves','after');
   
   h = addBuffer(h,findPulses(h,'activeChannels',{'Data'},'contains'),repolarization,{'AOM','Signal'},'Repolarization','after');
   
   h = addBuffer(h,findPulses(h,'activeChannels',{'Data'},'contains'),collectionBuffer,{'Signal'},'Data collection buffer','before');

   dataLocations = findPulses(h,'activeChannels',{'Data'},'contains');
   dataDuration = h.userSequence(dataLocations(1)).duration;
   
   %Negative number indicates DAQ pulse must be sent first
   if AOM_DAQCompensation > 0
      %Adds pulse with AOM on to account for lag between AOM and DAQ
      h = addBuffer(h,findPulses(h,'activeChannels',{'Data'},'contains'),AOM_DAQCompensation,{'AOM','Signal'},'DAQ delay compensation','before');
      
      %Shortens the repolarization time in accordance with the added time above
      newRepolarization = repolarizationDuration - AOM_DAQCompensation;
      repolarizationAddresses = findPulses(h,'notes','Repolarization','contains');
      h = modifyPulse(h,repolarizationAddresses,'duration',newRepolarization);
   else
      %Adds pulse with DAQ on to account for lag between DAQ and AOM
      h = addBuffer(h,findPulses(h,'activeChannels',{'Data'},'contains'),abs(AOM_DAQCompensation),{'Signal'},'AOM/DAQ delay compensation','before');
      
      %Shortens the data collection time in accordance with the added time above
      newDataDuration = dataDuration - abs(AOM_DAQCompensation);
      dataAddresses = findPulses(h,'notes','data collection','contains');
      h = modifyPulse(h,dataAddresses,'duration',newDataDuration);
   end
end