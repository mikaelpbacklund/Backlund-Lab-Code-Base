seq = ex.pulseBlaster.userSequence;
xax = [];
yax = [];
for ii = 1:numel(seq)
    binChannels = seq(ii).channelsBinary;
    binChannels = binChannels(~isspace(binChannels));
    if ii == 1
        xax = 0;
        for jj = 1:numel(binChannels)
            yax(ii,jj) = (jj-1)*2+.5; %#ok<*SAGROW>
        end
    else
        xax = [xax,xax(end)+seq(ii-1).duration]; %#ok<*AGROW>
        for jj = 1:numel(binChannels)
            yax(ii,jj) = str2double(binChannels(jj))+(jj-1)*2+.5; %#ok<*SAGROW>
        end        
    end
end
close all
myfig = figure(1);
myax = axes(myfig);
for jj = 1:numel(binChannels)
    stairs(myax,xax,yax)
end

