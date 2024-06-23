%% Here are links to pages I found helpful from the matlab help center

%Pulling information from a structure that isn't 1x1
%https://www.mathworks.com/help/matlab/matlab_prog/access-multiple-elements-of-a-nonscalar-struct-array.html

%Check if certain conditions about variables are met
%https://www.mathworks.com/help/matlab/matlab_prog/argument-validation-functions.html

%Set and Get functions for properties allowing you to modify what happens
%whenever they are called
%https://www.mathworks.com/help/matlab/matlab_oop/property-set-methods.html

%% Notes
%When using the "set" function for object properties that are structures,
%the second input (value you want to set it to) will be the entire
%structure with the specific field you are setting already changed. This
%makes it pretty useless, because you can't actually tell what was changed
%and thus cannot modify how that change happens. I am thoroughly annoyed
%about this

%% Random snippets of code

%How to break down multi-dimensional structures into more usable parts 
myStruct.x = 1;
myStruct(2).x = 2;
cellFormatOfX = {myStruct};
%Final output will be the equivalent of the following:
equivalentX = {1,2};


%This sets every cell to be the same value in the way one might expect the
%following to do:
%h.data{1}{:} = resetValue;
%The above doesn't work due to internal matlab shenanigans but, by using the
%deal function, the same thing can be accomplished
myCell = num2cell(zeros(N,M));
[myCell{:}] = deal([1,2,3,4]);