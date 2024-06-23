global master

%Load pulse sequence on the GUI to make things easy
%additionally, load all instruments (DAQ, pulse blaster, stage, RF)

%These are the pulse addresses you need to identify that you want to
%change
scanAddresses = [3 5];%Fake numbers

%What values you want the pulses above to take
%The first values are for the first pulse address, the second for the
%second address
scanValues{1} = [50 900 1100 1500];
scanValues{2} = [3000 500 700 2000];

%Number of iterations to do
nIterations = 1;

%Runs a stage optimization then sets the current time as the most recent
%time an optimization was run
% stageOptimization
lastOptTime = datetime;

%Preallocation
myDataIterations = zeros(1,numel(scanValues{1}));
myDataSum = myDataIterations;

for nIt = 1:nIterations %Each iteration
   
   for dataPoint = 1:numel(scanValues{1}) %Each data point in the scan
      
      
      if datetime-lastOptTime > duration(0,5,0)%Check if last optimization was over 5 mins ago
         %Runs stage optimization. Use GUI to set settings for optimization
         %process
         stageOptimization
         
         lastOptTime = datetime;%Sets new time for last optimization
      end
      
      %This changes the duration of each specified address
      for nAddress = 1:numel(scanAddresses)
         master.PB.sequence(scanAddresses(nAddress)).duration = scanValues{nAddress}(dataPoint);
      end
      
      %Sets the new pulse blaster sequence
      PBFinalize
      
      %Runs the pulse sequence and gets the data
      [sig,ref] = PBRun;
      
      myDataSum(dataPoint) = myDataSum(dataPoint) + (ref-sig)/ref;
      myDataIterations(dataPoint) = myDataIterations(dataPoint) + 1;
      
      dataToPresent = myDataSum ./ myDataIterations;%Finds the current average for all data points
      dataToPresent(isnan(dataToPresent)) = 0;%Divide by 0 replacement
      
      plot(dataToPresent)
      
   end
   
   
end

