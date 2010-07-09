// Created by Max Howell on 09/07/2010.

@implementation NSXMLNode(mxcl)

-(NSXMLNode*)childNamed:(NSString*)name
{
   NSEnumerator* e = [self.children objectEnumerator];
   NSXMLNode *node;
   while (node = [e nextObject]) 
      if ([node.name isEqualToString:name])
         return node;
   return nil;
}

-(NSArray*)childrenAsStrings
{
   NSMutableArray* strings = [NSMutableArray arrayWithCapacity:self.children.count];
   NSEnumerator* e = [self.children objectEnumerator];
   NSXMLNode* node;
   while (node = [e nextObject])
      [strings addObject:[node stringValue]];
   return strings;
}

@end
