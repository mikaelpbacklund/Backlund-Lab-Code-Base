function [data_matrix] = OdometerLoops(loopmatrix,datafunction)
%Replacement for nested for loops with n-dimensional data output

%Each element in loopmatrix input represents a nested loop where the first
%element is the highest order loop (the one which changes the fewest number
%of times). the value of each element is the number of times that
%particular loop will run for. data_matrix output will have the same number
%of dimensions as the loopmatrix input has elements

%Datafunction is the function which actually takes whatever data you need.
%for it to be compatible with this OdometerLoops function, it must require
%no inputs and only output a single value. the best example of this is the
%RecordValue function.

%Below is an example of the type of nested loop you can replace with this
%function:
    %for ii = 1:5
        %for jj = 1:7
            %data_matrix(ii,jj) = RecordValue();
        %end
    %end
    
    %data_matrix = OdometerLoops([5 7],RecordValue);

%Preparing variables
iscorrect = false;
odomatrix = ones(1,length(loopmatrix));
data = zeros(1,prod(loopmatrix));
n = 0;

%Main loop. every iteration, the next data point is taken and the odometer
%is incremented by 1
while ~iscorrect 
    n = n+1;  
    data(n) = feval(datafunction); 
    noturnover = false;
    ndigit = 1;
    odomatrix(end) = odomatrix(end)+1;
    
    %Increments lowest digit first (above). If lowest digit hits the limit,
    %turns lowest digit to 1 and increments next digit. Does this until
    %upper limit hits maximum then stops the entire loop
    while ~noturnover        
        revdigit = 1 + length(loopmatrix) - ndigit;        
        if odomatrix(revdigit) == loopmatrix(revdigit)+1  %Is digit max value          
            ndigit = ndigit + 1;
            odomatrix(revdigit) = 1;            
            if revdigit ~= 1 %If this is not highest order loop
                odomatrix(revdigit-1) = odomatrix(revdigit-1)+1;
            else
                iscorrect = true;
                noturnover = true;
            end            
        else            
            noturnover = true;
        end        
    end
    
end

%Reshapes data matrix from vector to the shape that would be obtained
%naturally from nested for loops
data_matrix = reshape(data,flip(loopmatrix));
data_matrix = permute(data_matrix,flip(1:length(loopmatrix)));
end

