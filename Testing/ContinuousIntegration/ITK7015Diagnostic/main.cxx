#include "itkMetaImageIOFactory.h"

#if defined(ITK7015_DIAGNOSTIC)
int itkImageToVideoFilterTestDiagnostic(int argc, char * argv[]);
#else
int itkImageToVideoFilterTest(int argc, char * argv[]);
#endif

int main(int argc, char * argv[])
{
  itk::MetaImageIOFactory::RegisterOneFactory();
#if defined(ITK7015_DIAGNOSTIC)
  return itkImageToVideoFilterTestDiagnostic(argc, argv);
#else
  return itkImageToVideoFilterTest(argc, argv);
#endif
}
