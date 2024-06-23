classdef testObj
properties
   y
   z
end
properties (Dependent)
   x
end
methods

   function h = set.x(h,val)
      % val.second = 3;
      assignin('base',"val",val)
      h.y = val;
   end

   function s = get.x(h)
      h.z = true;
      s = h.y;
   end
end
end