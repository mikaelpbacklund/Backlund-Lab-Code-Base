function  PBTimeCalculator(sequence)
%Calculates the signal, reference, and total time of sequence input

%PBTimeCalculator v1.0 6/20/22

global master

totalTime = 0;
refTime = 0;
sigTime = 0;

%Creates list of loops within the sequence based on end loop locations
loopTracker = [];
nn = 1;
for ii = 1: numel(sequence)
   if strcmp(sequence(ii).direction,"END_LOOP")
      currloop = [sequence(ii).contextinfo ii];
      loopTracker(nn,:) = currloop; %#ok<AGROW>
      nn = nn+1;
   end
end

%For each pulse in the sequence, determine if it is within
%any loops; if it is within any, multiply the duration by
%the number of loops to get the total duration for that
%pulse. If the counter is on, add to signal or reference as appropriate.
%Sum all durations to get the total time
for ii = 1:numel(sequence)
   currTime = sequence(ii).duration;
   if ~isempty(loopTracker)
      betweenLoops = [(ii > loopTracker(:,1)) (ii <= loopTracker(:,2))];
      betweenLoops = all(betweenLoops,2);
      nLoops = [sequence(betweenLoops).contextinfo];
      nLoops(end+1) = 1; %#ok<AGROW>   Added in case it is not within any loops
      nLoops = prod(nLoops);
   else
      nLoops = 1;
   end
   totalTime = totalTime + (currTime * nLoops);
   if str2double(sequence(ii).binaryoutput(end-1))
      if str2double(sequence(ii).binaryoutput(end-2))
         sigTime = sigTime + (currTime * nLoops);
      else
         refTime = refTime + (currTime * nLoops);
      end
   end
end

master.PB.sequenceDuration = totalTime;
master.PB.referenceDuration= refTime;
master.PB.signalDuration = sigTime;


end

