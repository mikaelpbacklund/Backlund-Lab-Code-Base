function h = completeSequence(h,p,varargin)
%Finishes sequence creation for templates

%Adjust sequence using standard template modification
if all(isfield(p,{'intermissionBufferDuration','repolarizationDuration',...
        'collectionBufferDuration','AOMCompensation','IQBuffers','dataOnBuffer','extraBuffer'}))

    %See function for more detail. Modifies base sequence with necessary things to function properly
    h = standardTemplateModifications(h,p.intermissionBufferDuration,p.repolarizationDuration,...
        p.collectionBufferDuration,p.AOMCompensation,p.IQBuffers,p.dataOnBuffer,p.extraBuffer);
else
    warning('Could not perform standard template modifications. Not all parameters given')
    assignin("base","p",p)
end

%Change intermission pulses to account for mean of compensating scan
if isfield(p,'useCompensatingPulses') && p.useCompensatingPulses
   compensatingPulses = findPulses(h,'notes','intermission','contains');
   if nargin > 2
       durationsAdded = varargin{1};
   else
       durationsAdded = diff(p.scanBounds)/2;
   end
   h = modifyPulse(h,compensatingPulses,'duration',p.intermissionBufferDuration+durationsAdded);
end

%Changes number of loops to match desired time
h = adjustSequence(h);
h.nTotalLoops = floor(p.sequenceTimePerDataPoint/h.sequenceDurations.adjusted.totalSeconds);
h = sendToInstrument(h);

end