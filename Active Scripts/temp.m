clear ex
if ~exist('ex','var')
   ex = experiment;
end

initialTime = datetime;
%Windfreak connection
if isempty(ex.windfreak_RF)
   ex.windfreak_RF = RF_generator('windfreak_RF');
   ex.windfreak_RF = connect(ex.windfreak_RF);
end

ex.windfreak_RF.uncommonProperties.bypassPreCheck = true;

ex.windfreak_RF.enabled = true;

ex.windfreak_RF.amplitude = 20;

disp('Kyle it started')
%%
connectionTime = seconds(datetime - initialTime);

for ii = 1:6
    if mod(ii,2) == 1
        ex.windfreak_RF.frequency = 1;
    else
        ex.windfreak_RF.frequency = 1.1;
    end
    setTimes(ii) = seconds(datetime - initialTime);
end

ex.windfreak_RF = queryFrequency(ex.windfreak_RF);

queryTime = seconds(datetime - initialTime);

timeDifferentials = diff([connectionTime setTimes queryTime]);

