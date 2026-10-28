source, destination = ARGV
text = File.read(source)
original = '        ITK_TEST_EXPECT_EQUAL(frame->GetPixel(itk::MakeIndex(idx[1], idx[2])), it.Get());'
abort 'Expected original assertion exactly once' unless text.scan(original).length == 1
replacement = <<'CPP'
        const auto actual = frame->GetPixel(itk::MakeIndex(idx[1], idx[2]));
        const auto expected = it.Get();
        if (actual != expected)
        {
          static_assert(sizeof(PixelType) == sizeof(std::uint32_t));
          std::uint32_t actual_bits{}, expected_bits{};
          std::memcpy(&actual_bits, &actual, sizeof(actual_bits));
          std::memcpy(&expected_bits, &expected, sizeof(expected_bits));
          std::cerr << "Pixel mismatch index=" << idx << " frame=" << idx[frameAxis]
                    << std::setprecision(std::numeric_limits<PixelType>::max_digits10)
                    << " actual=" << actual << " expected=" << expected
                    << std::hexfloat << " actual_hex=" << actual << " expected_hex=" << expected
                    << std::defaultfloat << std::hex
                    << " actual_bits=" << actual_bits
                    << " expected_bits=" << expected_bits
                    << std::dec << std::endl;
          return EXIT_FAILURE;
        }
CPP
text.sub!(original, replacement.chomp)
text.sub!('itkImageToVideoFilterTest(int argc, char * argv[])',
          'itkImageToVideoFilterTestDiagnostic(int argc, char * argv[])')
text.sub!('#include <string>', "#include <string>\n#include <cstring>\n#include <cstdint>\n#include <iomanip>\n#include <limits>")
File.write(destination, text)
