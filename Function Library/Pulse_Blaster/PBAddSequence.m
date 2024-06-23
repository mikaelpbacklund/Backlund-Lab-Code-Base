function PBAddSequence
%Adds current values in master.PB.command to master.PB.sequence

%PBAddSequence v2.0 5/26/22

global master 

InitializationCheck('PB')

if ~isfield(master.PB,'command')
   error('No command given. Use master.PB.command.xxx')
end

%Possible directions
%CONTINUE: continue to next instruction
%STOP: stop execution of program with no regard to output states
%LOOP: specify beginning of loop
%END_LOOP: specify end of loop
%JSR: execution jumps to beginning of subroutine
%RTS: execution returns out of subroutine after JSR
%BRANCH: execution continues at a new instruction address
%LONG_DELAY: delays for a long period
%WAIT: execution stops and waits for software/hardware trigger

%contextinfo required for the following:
%LOOP: number of desired loops
%END_LOOP: address of beginning loop
%JSR: address of first subroutine instruction
%BRANCH: address of next instruction
%LONG_DELAY: multiplier of delay (>=2)
if isfield(master.PB.command,'direction')
    aa = master.PB.command.direction;
    if strcmp(aa,'CONTINUE') || strcmp(aa,'STOP') || strcmp(aa,'RTS') || strcmp(aa,'WAIT')
        master.PB.command.contextinfo = 0;
    elseif strcmp(aa,'LOOP') || strcmp(aa,'JSR') || strcmp(aa,'BRANCH') || strcmp(aa,'END_LOOP') || strcmp(aa,'LONG_DELAY')
        %do nothing
    else
        error("master.PB.command.direction must be one of the following: 'CONTINUE' 'STOP' 'RTS' 'WAIT' 'LOOP' 'JSR' 'BRANCH' 'END_LOOP' 'LONG_DELAY'")
    end
else
    error("Pulse blaster direction not given. Must be one of the following: 'CONTINUE' 'STOP' 'RTS' 'WAIT' 'LOOP' 'JSR' 'BRANCH' 'END_LOOP' 'LONG_DELAY'")
end

if ~isfield(master.PB.command,'output')
    error("Pulse blaster output not given")
end

if ~isfield(master.PB.command,'contextinfo')
    error("Pulse blaster required contextual information not given")
end

if isfield(master.PB.command,'duration')
    aa = master.PB.command.duration;
    if isscalar(aa) && ~isstring(aa)
        if aa <= 0 && aa > 8.589e9
            error("Pulse blaster duration must be between 0 and 8.589e9")
        end
    else
        error("Pulse blaster duration must be scalar and not a string")        
    end
else
    error("Pulse blaster duration not given")
end

if ~isfield(master.PB,'nchannels')
   master.PB.nchannels = 6;
end

if ~isfield(master.PB.command,'description')
   master.PB.command.description = '';
end

master.PB.command.binaryoutput = PBDec2Bin(master.PB.command.output);

if isfield(master.PB,'sequence')
   master.PB.sequence(end+1) = master.PB.command;
else
   master.PB.sequence = master.PB.command;
end

master.PB.command = rmfield(master.PB.command,'binaryoutput');

end