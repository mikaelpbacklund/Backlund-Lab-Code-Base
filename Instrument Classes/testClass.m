classdef testClass
   properties
      queriedProperty
      setProperty
   end

   methods

   function val = get.queriedProperty(h)
      if h.setProperty
         val = 1;
      else
         val = 2;
      end
   end

   function h = myFunc(h)
      disp(h.queriedProperty)
   end

   end
end