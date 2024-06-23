function PBFinalize
%Exports current pulse sequence in master.PB.sequence to pulse blaster

%PBFinalize v2.0 5/26/22

global master

InitializationCheck('PB')

if master.PB.useInterpreter
    trueseq = PBInterpreter;    
else
    trueseq = master.PB.sequence;
end
master.PB.truesequence = trueseq;
PBTimeCalculator(master.PB.truesequence)

calllib(master.PB.dllname,'pb_start_programming',0);
loopTracker = [];
for ii = 1 : length(trueseq)
    aa = trueseq(ii);
    switch aa.direction
        case 'CONTINUE'
            op_code = 0;
        case 'STOP'
            op_code = 1;
        case 'LOOP'
            op_code = 2;
            loopTracker(end+1) = ii-1; %#ok<AGROW>
        case 'END_LOOP'
            op_code = 3;
            if strcmp(master.comp,'NV2')
               if isempty(loopTracker)
                  error('Attempted to end loop while no loop has begun')
               end
               aa.contextinfo = loopTracker(end);
               loopTracker(end) = [];
            end
        case 'JSR'
            op_code = 4;
        case 'RTS'
            op_code = 5;
        case 'BRANCH'
            op_code = 6;
        case 'LONG_DELAY'
            op_code = 7;
        case 'WAIT'
            op_code = 8;
    end
    
    if isstring(aa.output)
        aa.output = hex2dec(aa.output);
    end

master.pulseOrder(ii) = calllib(master.PB.dllname,'pb_inst_pbonly',aa.output,op_code,aa.contextinfo,round(aa.duration));
    
end

calllib(master.PB.dllname,'pb_stop_programming');

if master.notifications
    fprintf('Pulse blaster sequence finalized\n')
end

end