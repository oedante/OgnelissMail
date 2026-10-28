// Проверка цепочки до ЦС без общего хранилища доверия (ЦС Минцифры по ящикам).
// Сертификаты — тестовые, выпущены openssl только для этого теста.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/security/ca_chain_verifier.dart';

const _ca = 'MIIDRTCCAi2gAwIBAgIURckovFdsLJrCv0YHkxk2nbRjDBowDQYJKoZIhvcNAQELBQAwMjELMAkGA1UEBhMCUlUxDTALBgNVBAoMBFRlc3QxFDASBgNVBAMMC1Rlc3QgU3ViIENBMB4XDTI2MTAwNjAxNTEyNloXDTQ2MTAwMTAxNTEyNlowMjELMAkGA1UEBhMCUlUxDTALBgNVBAoMBFRlc3QxFDASBgNVBAMMC1Rlc3QgU3ViIENBMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA5ZuIZdhQnyQIjTGz++fYNkOBbNrwJw9yufhKGSje59avHh1+F+qfD3BoiypvERyt3lKEf8of8f4PseQ6CjA+qS68009C1EQkFAJ0/xGaMV9su9g+rNhoLtx0U0geXBz2ymUTBenOlz3+MdY/kkwyQD6EHuRu9RAD1zj7G3biYhPhEWxaThvSsc/Y3izOC3aI7DCyFdrAXL3Gswdnce13SSkcwnxO/IC6bEviW4ccaxFHPKpSMFeRM0f21mBlQTVjF01TQCtq1MIaRD2qC/yLIsUcWTFKzSOybWn9QhLrSAxbrCQDg5EXARFFuZCVGMTzlooBbxZ54rtKgwsvigrIvwIDAQABo1MwUTAdBgNVHQ4EFgQUI2+PFfEHKGXqpOJywjAMRy5qMKgwHwYDVR0jBBgwFoAUI2+PFfEHKGXqpOJywjAMRy5qMKgwDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEAXkeq+1fN69LI6DeJeAxQvajOHrj5xoT61nzxYJM3RtdzJlYc+FoEN/i07ywaIy7N8do8N6ULa0cK0OloEUDG7fYIpZPf8ZLy3I6TJ/sOP5/mw8CAEF/T+oKpSPbyLjCByhVNOyRbAXQQVzYOItrL3qXj39oM3Sm7FVzV9ZxNkX2kGphcCPqrAzwmYL3AMc1Bx28ZlRIkh/+LhVam65SRAL8lJcRTnJnrFTu5G16fyaVliff3kLBI7UlW5WaVHIbkBpDJT6ASdLTm9nfVnrilKSlXR2y2EGkSo1RmkrcW3wRYFdMEZD6D7t8yfzExKeJCqVW75VWgTbNWs9THspIKcw==';
const _leaf = 'MIIDPTCCAiWgAwIBAgIUXOCThf9c07OyRPp0LGSvwFeX2ecwDQYJKoZIhvcNAQELBQAwMjELMAkGA1UEBhMCUlUxDTALBgNVBAoMBFRlc3QxFDASBgNVBAMMC1Rlc3QgU3ViIENBMB4XDTI2MTAwNjAxNTEyNloXDTQ1MTIwNTAxNTEyNlowFzEVMBMGA1UEAwwMbWFpbC5jb3JwLnJ1MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAoMCId7gs2MXErAikitVWZxCpQT/XGLALwVTPXoF8ujTUTTJt4k+tLInsiqRRK+kxHCaILC18vaMmur9O4HnyoIpGom4+Crq1ml9z0834sPC/Ex+7DNZO5sKIaqLI6ehqOK6DItpbuCPjMg+sE06IpRdzWtU3R9D5u4RXo8zs7Phzmgx4D4rAmzfioNoW1+xVvLCiE8p5a2u7XgJHJIzlYg/gk7XtGATpgp/+1OAv64og0CfyqnGaBHJKM0Skmru6IyOVnhJP1bHam5SlYnXVMXGLT6G7bvpmMttZWX9gItzSrUh+3+oN3htwCCfg00hPXcHx4TaSNXwR8+sQynW8KwIDAQABo2YwZDAiBgNVHREEGzAZggxtYWlsLmNvcnAucnWCCSouY29ycC5ydTAdBgNVHQ4EFgQUuJgmSV+B6oAbfrItYAWwG2dfx1swHwYDVR0jBBgwFoAUI2+PFfEHKGXqpOJywjAMRy5qMKgwDQYJKoZIhvcNAQELBQADggEBANWkvG0HQgzfG3nMBOs1SOcYV5Wt8rJNvwlJcwZ7/ETohBucfMmRUBbvLiBva05HzS2uX7T0/FTy1a10HcFa6ibpW88dssKB7Xy8JtUw3D9slukPjQP78iWnrEsfpw+RdDQFZJK70kzGXc6uPmxX5Bs4gzCH6rnM3xFHpa+fuJzsbINdSGxlQCSw+ZQhjre9o1pOYxxcZpkRZlNFBn4XAW8w8Zxo8beC+kzgjZSpQgq4swrhGjyTqFfe69zAzfHiZ7T+/8Rj5Ss3uHuy0VkBJkwInKJ31JUiSLOm8h87Mw9g1DQQRpvYKxfeCqbeCtTiwYPPIuVpqIFS+K0nHJLuqEE=';
const _other = 'MIIDBzCCAe+gAwIBAgIUGACLu1T4/Ao/mXhLStWyzmXkZ84wDQYJKoZIhvcNAQELBQAwEzERMA8GA1UEAwwIT3RoZXIgQ0EwHhcNMjYxMDA2MDE1MTI2WhcNNDYxMDAxMDE1MTI2WjATMREwDwYDVQQDDAhPdGhlciBDQTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKLFtiq0R4nAbt63nV/Qedony03eb6zzk9LJUmGIeUG+i3tiu/EM+iCsNCHbIYR3AODsqqXxGR1FvqwQ0zQnbZHGrNK204UibIQbe+aT7WCiIRoDrq4cnyGTI1a4aQ/GuCAGJggNh6fzOxxupeThPdSUAnU2tLHyyaWBY1f+knHhUOWsxsjyWcMYAVwPuGAxoKJWmYE217dybGQEH48NBnVS7+3rvpiCbnUcTi31lMBM6pfL9jsvLNN5kr3qNMkr6k8O/EbT6uQrDCvpiqxOIVvS+pAGZNPw+Y9Lj+cvU1twzLMqGDrxCsuh9VxEPvQxBaghmQZgATv3M6HKG+US/GsCAwEAAaNTMFEwHQYDVR0OBBYEFCu+5pNPfNmwZvRVvgxNqiLiPdqmMB8GA1UdIwQYMBaAFCu+5pNPfNmwZvRVvgxNqiLiPdqmMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQELBQADggEBABky3AuZ5Dt66w5OjThxzSORxN7os6/vlJG5CtEaBu+WAsQt0FirodSr9DWsJjDhx66B14pQEjRv2//pK0kCPjDt7Qj9OllZy7nWSsmsfuvwuX1VozxGxnabpZUdinv84jYSZwld3oN7z3bIut6pcrOyNzBDCtNpg6MTFeHapfAO7SRHd5Uh/mFxc5XJb8SJzRL75K4x7uKlgZpRm9quJKI4e6nWDldvlXGagW9bgTO0mQmUJxCVp3zs9nNX/cS6460ezQhduK98mb/955Ia0MGn48G4Jfz8dpIqnoiqrni5/QDgmhx8MBL6TDhYqVPqIe72at3Jj687Rx5GnG+ocO8=';

void main() {
  final ca = base64.decode(_ca);
  final leaf = base64.decode(_leaf);
  final other = base64.decode(_other);
  final now = DateTime.utc(2027, 1, 1);

  test('выпущен ЦС и подходит хосту — принимается', () {
    expect(CaChainVerifier.verify(leafDer: leaf, issuers: [ca], host: 'mail.corp.ru', now: now), isTrue);
  });

  test('шаблон *.corp.ru — одна метка слева', () {
    expect(CaChainVerifier.verify(leafDer: leaf, issuers: [ca], host: 'owa.corp.ru', now: now), isTrue);
    expect(CaChainVerifier.verify(leafDer: leaf, issuers: [ca], host: 'a.b.corp.ru', now: now), isFalse);
  });

  test('чужой хост — отказ', () {
    expect(CaChainVerifier.verify(leafDer: leaf, issuers: [ca], host: 'mail.google.com', now: now), isFalse);
  });

  test('другой ЦС — отказ', () {
    expect(CaChainVerifier.verify(leafDer: leaf, issuers: [other], host: 'mail.corp.ru', now: now), isFalse);
  });

  test('истёкший сертификат — отказ', () {
    expect(
        CaChainVerifier.verify(leafDer: leaf, issuers: [ca], host: 'mail.corp.ru', now: DateTime.utc(2099)),
        isFalse);
  });
}
